pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"

Singleton {
    id: root

    // Auto-detected on startup; Settings.hyprLuaConfig can force true if detection misses
    property bool _luaDetected: false
    readonly property bool _useLua: Settings.hyprLuaConfig || _luaDetected

    Process {
        id: _luaCheck
        command: ["sh", "-c", "[ -f ~/.config/hypr/hyprland.lua ]"]
        onExited: (code) => { root._luaDetected = (code === 0) }
        Component.onCompleted: running = true
    }

    FileView {
        id: _pidStatFile
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    property var _parentPidCache: ({})
    readonly property int _parentPidCacheTtlMs: 1500
    readonly property int _parentPidCacheLimit: 128

    function _quote(value): string {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    function _value(value): string {
        const text = String(value)
        return /^-?\d+$/.test(text) ? text : _quote(text)
    }

    function _dispatch(dispatcher, args): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        const cmd = ["hyprctl", "dispatch", dispatcher]
        if (args !== undefined && args !== null && String(args).length > 0)
            cmd.push(String(args))
        Quickshell.execDetached(cmd)
    }

    // Live, cached Hyprland clients, no subprocess. lastIpcObject carries
    // pid, class, initialClass, title, workspace and address.
    function _clients() {
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const out = []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const c = t ? t.lastIpcObject : null
            if (c && c.address) out.push(c)
        }
        return out
    }

    function _hereWorkspaceId() {
        return Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id ?? -1) : -1
    }

    function _toPid(value): int {
        const p = Number(value)
        return isFinite(p) && p > 0 ? Math.floor(p) : -1
    }

    function _norm(value): string {
        let text = String(value || "").trim().toLowerCase()
        if (text.endsWith(".desktop")) text = text.slice(0, -8)
        return text
    }

    function _compact(value): string {
        return root._norm(value).replace(/[^a-z0-9]/g, "")
    }

    function _chooseSource(pool) {
        return root._chooseMatchingSource(pool || [], function() { return true })
    }

    function _chooseMatchingSource(clients, matches) {
        const hereId = root._hereWorkspaceId()
        let bestAny = null
        let bestElsewhere = null

        for (let i = 0; i < clients.length; i++) {
            const c = clients[i]
            if (!c || !c.address || !c.workspace || !matches(c)) continue

            const rank = c.focusHistoryID ?? 9999
            if (!bestAny || rank < (bestAny.focusHistoryID ?? 9999))
                bestAny = c
            if (c.workspace.id !== hereId && (!bestElsewhere || rank < (bestElsewhere.focusHistoryID ?? 9999)))
                bestElsewhere = c
        }

        return bestElsewhere || bestAny
    }

    function _pidMatches(clients, pid) {
        const out = []
        for (let i = 0; i < clients.length; i++) {
            const c = clients[i]
            if (root._toPid(c.pid) === pid) out.push(c)
        }
        return out
    }

    function _readProcStat(pid): string {
        if (pid <= 1) return ""
        try {
            _pidStatFile.path = "/proc/" + pid + "/stat"
            _pidStatFile.reload()
            if (!_pidStatFile.waitForJob()) return ""
            return _pidStatFile.text()
        } catch (e) {
            return ""
        }
    }

    function _pruneParentPidCache(now): void {
        const cache = root._parentPidCache
        const keys = Object.keys(cache)
        for (let i = 0; i < keys.length; i++) {
            const item = cache[keys[i]]
            if (!item || now - Number(item.time || 0) > root._parentPidCacheTtlMs)
                delete cache[keys[i]]
        }

        const kept = Object.keys(cache)
        if (kept.length > root._parentPidCacheLimit)
            root._parentPidCache = ({})
    }

    function _parentPid(pid): int {
        const p = root._toPid(pid)
        if (p <= 1) return -1

        const now = Date.now()
        const key = String(p)
        const cached = root._parentPidCache[key]
        if (cached && now - Number(cached.time || 0) <= root._parentPidCacheTtlMs)
            return root._toPid(cached.value)

        const stat = root._readProcStat(p)
        const end = stat.lastIndexOf(")")
        let parent = -1
        if (end >= 0) {
            const parts = stat.slice(end + 1).trim().split(/\s+/)
            // /proc/<pid>/stat fields after comm start with: state ppid ...
            parent = parts.length >= 2 ? root._toPid(parts[1]) : -1
        }

        root._parentPidCache[key] = { value: parent, time: now }
        if (Object.keys(root._parentPidCache).length > root._parentPidCacheLimit)
            root._pruneParentPidCache(now)
        return parent
    }

    function _senderPid(notification): int {
        const hints = notification?.hints ?? {}
        const candidates = [
            hints["sender-pid"],
            hints["sender_pid"],
            hints["senderPid"],
            hints["process-id"],
            hints["process_id"],
            hints["pid"]
        ]

        for (let i = 0; i < candidates.length; i++) {
            const pid = root._toPid(candidates[i])
            if (pid > 0) return pid
        }
        return -1
    }

    function _clientFromPidChain(clients, pid) {
        let p = root._toPid(pid)
        const seen = ({})

        // Each level is a blocking /proc read; a notifier sits a few forks below
        // its window (term → shell → notify-send), so 6 is ample without a deep scan.
        for (let depth = 0; p > 1 && depth < 6 && !seen[p]; depth++) {
            seen[p] = true

            const pool = root._pidMatches(clients, p)
            if (pool.length > 0)
                return root._chooseSource(pool)

            p = root._parentPid(p)
        }

        return null
    }

    function _classMatches(c, hint): bool {
        const h = root._norm(hint)
        if (h.length === 0) return false

        const cls  = root._norm(c.class)
        const init = root._norm(c.initialClass)
        const hc   = root._compact(h)

        return cls === h || init === h
            || (hc.length > 0 && (root._compact(cls) === hc || root._compact(init) === hc))
    }

    function _appMatches(c, appName): bool {
        const app = root._compact(appName)
        if (app.length === 0) return false

        const cls  = root._compact(c.class)
        const init = root._compact(c.initialClass)

        // Symmetric containment: "Telegram Desktop" ↔ org.telegram.desktop.
        // Length guard keeps short classes from matching everything.
        return cls === app || init === app
            || (cls.length  > 2 && (app.endsWith(cls)  || cls.endsWith(app)))
            || (init.length > 2 && (app.endsWith(init) || init.endsWith(app)))
    }

    // Web players report a browser window class instead of the player name.
    readonly property var _browserClasses: [
        "firefox", "librewolf", "zen", "waterfox",
        "chrome", "chromium", "brave", "edge", "opera", "vivaldi", "thorium"
    ]

    function focusMonitor(name: string): void {
        if (!name || name.length === 0) return
        if (_useLua)
            _dispatch("hl.dsp.focus({ monitor = " + _quote(name) + " })")
        else
            _dispatch("focusmonitor", name)
    }

    function focusWorkspace(workspaceId, monitorName): void {
        if (workspaceId === undefined || workspaceId === null || workspaceId < 0) return
        const targetMonitor = monitorName || ""
        if (targetMonitor.length > 0) focusMonitor(targetMonitor)
        if (_useLua)
            _dispatch("hl.dsp.focus({ workspace = " + _value(workspaceId) + " })")
        else
            _dispatch("workspace", workspaceId)
    }

    // Send the focused window to a workspace without following it (silent).
    function moveActiveToWorkspace(workspaceId): void {
        if (workspaceId === undefined || workspaceId === null || workspaceId < 1) return
        if (_useLua)
            _dispatch("hl.dsp.window.move({ workspace = " + _value(workspaceId) + ", silent = true })")
        else
            _dispatch("movetoworkspacesilent", workspaceId)
    }

    function focusWindow(address: string): void {
        if (!address || address.length === 0) return
        const target = address.startsWith("address:") ? address : "address:" + address
        if (_useLua)
            _dispatch("hl.dsp.focus({ window = " + _quote(target) + " })")
        else
            _dispatch("focuswindow", target)
    }

    function focusWorkspaceWindow(workspaceId, address): void {
        focusWorkspace(workspaceId, "")
        focusWindow(address)
    }

    // Resolve a notification to its source window (client), or null.
    // Precision order: sender PID chain → desktop-entry hint → appName →
    // appName resolved through the desktop-entry database. Ambiguity within a
    // match falls back to the most recently focused window of that app.
    function _matchNotificationClient(notification) {
        if (!notification) return null

        const clients = root._clients()
        if (clients.length === 0) return null

        const hints   = notification.hints ?? {}
        const pidHint = root._senderPid(notification)
        const deHint  = root._norm(notification.desktopEntry || hints["desktop-entry"] || "")

        // 1. Sender PID ancestry, catches notify-send/shell children inside a
        // terminal by walking up to the Hyprland client process.
        const pidMatch = root._clientFromPidChain(clients, pidHint)
        if (pidMatch && pidMatch.workspace) return pidMatch

        // 2. desktop-entry hint → window class.
        if (deHint.length > 0) {
            const bestDesktop = root._chooseMatchingSource(clients, c => root._classMatches(c, deHint))
            if (bestDesktop && bestDesktop.workspace) return bestDesktop
        }

        // 3. appName, directly against window classes.
        const appName = String(notification.appName || "")
        if (appName.length === 0) return null

        let bestApp = root._chooseMatchingSource(clients, c => root._appMatches(c, appName))

        // 4. appName → desktop entry → StartupWMClass/id, the same resolution
        // the workspace icons use; covers display names ("Spotify") whose
        // window class only the .desktop file knows.
        if (!bestApp) {
            const de = DesktopEntries.heuristicLookup(appName)
            const startupClass = de?.startupClass ? String(de.startupClass) : ""
            const desktopId = de?.id ? String(de.id) : ""
            if (startupClass.length > 0)
                bestApp = root._chooseMatchingSource(clients, c => root._classMatches(c, startupClass))
            if (!bestApp && desktopId.length > 0)
                bestApp = root._chooseMatchingSource(clients, c => root._classMatches(c, desktopId))
        }

        return (bestApp && bestApp.workspace) ? bestApp : null
    }

    function focusNotificationSource(notification): void {
        const c = root._matchNotificationClient(notification)
        if (c && c.workspace) focusWorkspaceWindow(c.workspace.id, c.address)
    }

    // Workspace id of the notification's source window, or -1 if not found.
    function notificationSourceWorkspace(notification): int {
        const c = root._matchNotificationClient(notification)
        return (c && c.workspace) ? (c.workspace.id ?? -1) : -1
    }

    // Jump to the window playing media. Matches player name → browser family →
    // song title in the window title.
    function focusMediaPlayer(playerName: string, songTitle: string): void {
        const clients = root._clients()
        if (clients.length === 0) return

        const name   = String(playerName || "").toLowerCase()
        const norm   = (s) => String(s || "").toLowerCase()

        let best = name.length > 0
            ? root._chooseMatchingSource(clients, c =>
                norm(c.class).includes(name) ||
                norm(c.initialClass).includes(name) ||
                norm(c.title).includes(name))
            : null

        if (!best && root._browserClasses.some(b => name.includes(b)))
            best = root._chooseMatchingSource(clients, c =>
                root._browserClasses.some(b =>
                    norm(c.class).includes(b) || norm(c.initialClass).includes(b)))

        if (!best && songTitle && songTitle.length > 4) {
            const t = songTitle.toLowerCase()
            best = root._chooseMatchingSource(clients, c => norm(c.title).includes(t))
        }

        if (best && best.workspace)
            focusWorkspaceWindow(best.workspace.id, best.address)
    }

    // Jump to the window behind a tray item, switching to its workspace. A tray
    // click should land you on the app, but many SNIs (Spotify) expose no
    // Activate method, so we resolve the window ourselves: match id / title /
    // tooltip against window classes, then the desktop-entry database (display
    // name → StartupWMClass) the way notifications do. Returns false when the
    // app has no live window (minimised-to-tray, background daemon) so the
    // caller can fall back to the item's own activation or menu.
    function focusTrayItem(id: string, title: string, tooltip: string): bool {
        const clients = root._clients()
        if (clients.length === 0) return false

        const hints = [id, title, tooltip].filter(s => s && String(s).length > 0)
        let best = null

        // 1. id / title / tooltip straight against window classes.
        for (let i = 0; i < hints.length && !best; i++)
            best = root._chooseMatchingSource(clients, c =>
                root._classMatches(c, hints[i]) || root._appMatches(c, hints[i]))

        // 2. desktop-entry resolution for display names whose window class only
        //    the .desktop file knows.
        for (let i = 0; i < hints.length && !best; i++) {
            const de = DesktopEntries.heuristicLookup(hints[i])
            const startupClass = de?.startupClass ? String(de.startupClass) : ""
            const desktopId    = de?.id ? String(de.id) : ""
            if (startupClass.length > 0)
                best = root._chooseMatchingSource(clients, c => root._classMatches(c, startupClass))
            if (!best && desktopId.length > 0)
                best = root._chooseMatchingSource(clients, c => root._classMatches(c, desktopId))
        }

        if (best && best.workspace) {
            focusWorkspaceWindow(best.workspace.id, best.address)
            return true
        }
        return false
    }
}
