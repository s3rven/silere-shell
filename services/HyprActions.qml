pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// window-matching + focus heuristics (notifications, tray, media) over the
// backend-neutral Compositor. dispatch to Hyprland lives here too so the
// Lua-config quirk stays in one place; Compositor calls _dispatch for Hyprland.
Singleton {
    id: root

    // Auto-detected on startup; Settings.hyprLuaConfig can force true if detection misses
    property bool _luaDetected: false
    readonly property bool _useLua: Settings.hyprLuaConfig || _luaDetected

    Process {
        id: _luaCheck
        command: ["bash", Quickshell.shellDir + "/scripts/install.sh", "--hypr-config-kind"]
        onExited: (code) => { root._luaDetected = (code === 0) }
        Component.onCompleted: running = Compositor.isHyprland
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

    // Hyprland dispatch; Compositor routes here for the Hyprland backend.
    function _dispatch(dispatcher, args): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        if (root._useLua && (dispatcher === "focusmonitor" || dispatcher === "workspace"
            || dispatcher === "movetoworkspacesilent" || dispatcher === "focuswindow")) {
            root._dispatchLua(dispatcher, args)
            return
        }
        const cmd = ["hyprctl", "dispatch", dispatcher]
        if (args !== undefined && args !== null && String(args).length > 0)
            cmd.push(String(args))
        Quickshell.execDetached(cmd)
    }

    function _dispatchLua(dispatcher, args): void {
        let call = ""
        if (dispatcher === "focusmonitor")
            call = "hl.dsp.focus({ monitor = " + _quote(args) + " })"
        else if (dispatcher === "workspace")
            call = "hl.dsp.focus({ workspace = " + _value(args) + " })"
        else if (dispatcher === "movetoworkspacesilent")
            call = "hl.dsp.window.move({ workspace = " + _value(args) + ", follow = false })"
        else if (dispatcher === "focuswindow")
            call = "hl.dsp.focus({ window = " + _quote(args) + " })"
        else return
        Quickshell.execDetached(["hyprctl", "dispatch", call])
    }

    // live neutral toplevels; each carries appId/cls/initialClass/title/pid/ref/wsId/wsRef
    function _clients() {
        return Compositor.toplevels || []
    }

    function _hereWorkspaceRef() {
        return Compositor.focusedWorkspaceRef
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
        const hereRef = root._hereWorkspaceRef()
        let bestAny = null
        let bestElsewhere = null

        for (let i = 0; i < clients.length; i++) {
            const c = clients[i]
            if (!c || !c.ref || c.wsId < 0 || !matches(c)) continue

            const rank = c.focusRank ?? 9999
            if (!bestAny || rank < (bestAny.focusRank ?? 9999))
                bestAny = c
            if (c.wsRef !== hereRef && (!bestElsewhere || rank < (bestElsewhere.focusRank ?? 9999)))
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

        // each level is a blocking /proc read; a notifier sits a few forks below its window, so 6 is ample
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

        const cls  = root._norm(c.cls)
        const init = root._norm(c.initialClass)
        const hc   = root._compact(h)

        return cls === h || init === h
            || (hc.length > 0 && (root._compact(cls) === hc || root._compact(init) === hc))
    }

    function _appMatches(c, appName): bool {
        const app = root._compact(appName)
        if (app.length === 0) return false

        const cls  = root._compact(c.cls)
        const init = root._compact(c.initialClass)

        // symmetric containment ("Telegram Desktop" ↔ org.telegram.desktop); length guard stops short classes matching everything
        return cls === app || init === app
            || (cls.length  > 2 && (app.endsWith(cls)  || cls.endsWith(app)))
            || (init.length > 2 && (app.endsWith(init) || init.endsWith(app)))
    }

    // Web players report a browser window class instead of the player name.
    readonly property var _browserClasses: [
        "firefox", "librewolf", "zen", "waterfox",
        "chrome", "chromium", "brave", "edge", "opera", "vivaldi", "thorium"
    ]

    // display names ("Spotify") whose window class only the .desktop file knows
    function _resolveByDesktopEntry(clients, name) {
        const de = DesktopEntries.heuristicLookup(name)
        const startupClass = de?.startupClass ? String(de.startupClass) : ""
        const desktopId    = de?.id ? String(de.id) : ""
        let best = null
        if (startupClass.length > 0)
            best = root._chooseMatchingSource(clients, c => root._classMatches(c, startupClass))
        if (!best && desktopId.length > 0)
            best = root._chooseMatchingSource(clients, c => root._classMatches(c, desktopId))
        return best
    }

    // resolve notif → source window: PID chain → desktop-entry → appName; ties fall back to most-recently-focused of that app
    function _matchNotificationClient(notification) {
        if (!notification) return null

        const clients = root._clients()
        if (clients.length === 0) return null

        const hints   = notification.hints ?? {}
        const pidHint = root._senderPid(notification)
        const deHint  = root._norm(notification.desktopEntry || hints["desktop-entry"] || "")

        // 1. sender PID ancestry — catches notify-send/shell children by walking up to the client
        const pidMatch = root._clientFromPidChain(clients, pidHint)
        if (pidMatch && pidMatch.wsId >= 0) return pidMatch

        // 2. desktop-entry hint → window class.
        if (deHint.length > 0) {
            const bestDesktop = root._chooseMatchingSource(clients, c => root._classMatches(c, deHint))
            if (bestDesktop && bestDesktop.wsId >= 0) return bestDesktop
        }

        // 3. appName, directly against window classes.
        const appName = String(notification.appName || "")
        if (appName.length === 0) return null

        let bestApp = root._chooseMatchingSource(clients, c => root._appMatches(c, appName))

        // 4. desktop-entry database, the same resolution the workspace icons use.
        if (!bestApp)
            bestApp = root._resolveByDesktopEntry(clients, appName)

        return (bestApp && bestApp.wsId >= 0) ? bestApp : null
    }

    function focusNotificationSource(notification): void {
        const c = root._matchNotificationClient(notification)
        if (c) Compositor.focusToplevel(c)
    }

    // Workspace id (as shown in the bar) of the notification's source window, or -1.
    function notificationSourceWorkspace(notification): int {
        const c = root._matchNotificationClient(notification)
        return c ? (c.wsId ?? -1) : -1
    }

    // jump to the media window; matches player name → browser family → song title
    function focusMediaPlayer(playerName: string, songTitle: string): void {
        const clients = root._clients()
        if (clients.length === 0) return

        const name   = String(playerName || "").toLowerCase()
        const norm   = (s) => String(s || "").toLowerCase()

        let best = name.length > 0
            ? root._chooseMatchingSource(clients, c =>
                norm(c.cls).includes(name) ||
                norm(c.initialClass).includes(name) ||
                norm(c.title).includes(name))
            : null

        if (!best && root._browserClasses.some(b => name.includes(b)))
            best = root._chooseMatchingSource(clients, c =>
                root._browserClasses.some(b =>
                    norm(c.cls).includes(b) || norm(c.initialClass).includes(b)))

        if (!best && songTitle && songTitle.length > 4) {
            const t = songTitle.toLowerCase()
            best = root._chooseMatchingSource(clients, c => norm(c.title).includes(t))
        }

        if (best) Compositor.focusToplevel(best)
    }

    // many SNIs (Spotify) expose no Activate, so match id/title/tooltip → class → desktop-entry db; false when no live window
    function focusTrayItem(id: string, title: string, tooltip: string): bool {
        const clients = root._clients()
        if (clients.length === 0) return false

        const hints = [id, title, tooltip].filter(s => s && String(s).length > 0)
        let best = null

        // 1. id / title / tooltip straight against window classes.
        for (let i = 0; i < hints.length && !best; i++)
            best = root._chooseMatchingSource(clients, c =>
                root._classMatches(c, hints[i]) || root._appMatches(c, hints[i]))

        // 2. desktop-entry database.
        for (let i = 0; i < hints.length && !best; i++)
            best = root._resolveByDesktopEntry(clients, hints[i])

        if (best) {
            Compositor.focusToplevel(best)
            return true
        }
        return false
    }
}
