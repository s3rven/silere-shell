pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    FileView {
        id: _pidStatFile
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    property var _parentPidCache: ({})
    readonly property int _parentPidCacheTtlMs: 1500
    readonly property int _parentPidCacheLimit: 128

    function _clients(): var {
        if (Compositor.isNiri) Compositor.refreshToplevels()
        return Compositor.toplevels || []
    }

    function _hereWorkspace(): var {
        const ws = Compositor.activeWorkspace(Compositor.focusedMonitor)
        return { ref: Compositor.focusedWorkspaceRef, name: ws ? String(ws.name ?? "") : "" }
    }

    // hyprland 0.57 gives every named workspace the same ref, so only the name tells two apart
    function _isHere(c, here): bool {
        return c.wsRef === here.ref && (here.ref > 0 || String(c.wsName ?? "") === here.name)
    }

    function _toPid(value): int {
        const p = Number(value)
        return isFinite(p) && p > 0 ? Math.floor(p) : -1
    }

    function _norm(value): string {
        let text = String(value || "").slice(0, 512).trim().toLowerCase()
        if (text.endsWith(".desktop")) text = text.slice(0, -8)
        return text
    }

    function _compact(value): string {
        return root._norm(value).replace(/[^a-z0-9]/g, "")
    }

    function _chooseSource(pool): var {
        return root._chooseMatchingSource(pool || [], function() { return true })
    }

    function _chooseMatchingSource(clients, matches, here = root._hereWorkspace()): var {
        let bestAny = null
        let bestElsewhere = null

        for (let i = 0; i < clients.length; i++) {
            const c = clients[i]
            if (!c || !c.ref || c.wsId === -1 || !matches(c)) continue

            const rank = c.focusRank ?? 9999
            if (!bestAny || rank < (bestAny.focusRank ?? 9999))
                bestAny = c
            if (!root._isHere(c, here) && (!bestElsewhere || rank < (bestElsewhere.focusRank ?? 9999)))
                bestElsewhere = c
        }

        return bestElsewhere || bestAny
    }

    function _pidMatches(clients, pid): var {
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
            const age = item ? now - Number(item.time || 0) : -1
            if (!isFinite(age) || age < 0 || age > root._parentPidCacheTtlMs)
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
        const age = cached ? now - Number(cached.time || 0) : -1
        if (cached && age >= 0 && age <= root._parentPidCacheTtlMs)
            return root._toPid(cached.value)

        const stat = root._readProcStat(p)
        const end = stat.lastIndexOf(")")
        let parent = -1
        if (end >= 0) {
            const parts = stat.slice(end + 1).trim().split(/\s+/)
            parent = parts.length >= 2 ? root._toPid(parts[1]) : -1
        }

        root._parentPidCache[key] = { value: parent, time: now }
        if (Object.keys(root._parentPidCache).length > root._parentPidCacheLimit)
            root._pruneParentPidCache(now)
        return parent
    }

    function _senderPid(notification): int {
        const keys = ["sender-pid", "sender_pid", "senderPid", "process-id", "process_id", "pid"]
        for (let i = 0; i < keys.length; i++) {
            const pid = root._toPid(notification?.hints?.[keys[i]])
            if (pid > 0) return pid
        }
        return -1
    }

    function _clientFromPidChain(clients, pid, followParents: bool): var {
        let p = root._toPid(pid)
        const seen = ({})

        for (let depth = 0; p > 1 && depth < 6 && !seen[p]; depth++) {
            seen[p] = true

            const pool = root._pidMatches(clients, p)
            if (pool.length > 0)
                return root._chooseSource(pool)

            // arrival-time effects must not wait on /proc; name matching still applies
            if (!followParents) break
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

        // a vendor word in front of the class ("Google Chrome" for chrome) needs a class longer than a common word:
        // "Claude Code", sent from kitty, took VS Code's "code" and turned away kitty raising its own window
        return cls === app || init === app
            || (app.length > 2 && cls.length > 2 && (cls.endsWith(app) || (cls.length > 4 && app.endsWith(cls))))
            || (app.length > 2 && init.length > 2 && (init.endsWith(app) || (init.length > 4 && app.endsWith(init))))
    }

    readonly property var _browserClasses: [
        "firefox", "librewolf", "zen", "waterfox",
        "chrome", "chromium", "brave", "edge", "opera", "vivaldi", "thorium"
    ]

    function _hasBrowserToken(value, browser): bool {
        return root._norm(value).split(/[.\s_-]+/).indexOf(browser) >= 0
    }

    function _resolveByDesktopEntry(clients, name, lookup): var {
        const identity = root._norm(name)
        if (identity.length === 0) return null
        // the optional lookup keeps this matching layer probeable without loading a desktop database; production callers continue to use the shared resolver
        return root._windowForDesktopEntry(clients,
            lookup ? lookup(identity) : DesktopEntries.heuristicLookup(identity))
    }

    function _windowForDesktopEntry(clients, de): var {
        const startupClass = de?.startupClass ? String(de.startupClass) : ""
        const desktopId    = de?.id ? String(de.id) : ""
        let best = null
        if (startupClass.length > 0)
            best = root._chooseMatchingSource(clients, c => root._classMatches(c, startupClass))
        if (!best && desktopId.length > 0)
            best = root._chooseMatchingSource(clients, c => root._classMatches(c, desktopId))
        return best
    }

    function _matchNotificationClient(notification, followPidParents: bool, clients, lookup): var {
        if (!notification) return null
        clients = clients ?? root._clients()
        if (clients.length === 0) return null

        const pidHint = root._senderPid(notification)
        const desktopId = String(notification.desktopEntry || notification.hints?.["desktop-entry"] || "")
            .slice(0, 512).trim().replace(/\.desktop$/i, "")

        const pidMatch = root._clientFromPidChain(clients, pidHint, followPidParents)
        if (pidMatch && pidMatch.wsId !== -1) return pidMatch

        if (desktopId.length > 0) {
            const direct = root._chooseMatchingSource(clients, c => root._classMatches(c, desktopId))
            if (direct) return direct
            const entry = lookup ? lookup(desktopId) : DesktopEntries.byId(desktopId)
            const byLauncher = root._windowForDesktopEntry(clients, entry)
            if (byLauncher) return byLauncher
        }

        const appName = root._norm(notification.appName)
        if (appName.length === 0) return null

        return root._chooseMatchingSource(clients, c => root._classMatches(c, appName))
            || root._chooseMatchingSource(clients, c => root._appMatches(c, appName))
            || root._resolveByDesktopEntry(clients, appName)
    }

    function focusNotificationSource(notification): void {
        const c = root._matchNotificationClient(notification, true)
        if (c) Compositor.focusToplevel(c)
    }

    // an app that raises its own window from its default action (kitty requests its own
    // activation token) knows which of its windows spoke; the match only knows the app, so
    // with several windows it can land on the wrong one after the app got it right
    function focusIsSourceApp(c, toplevels): bool {
        if (!c) return false
        const list = toplevels || []
        for (let i = 0; i < list.length; i++) {
            const t = list[i]
            if (!t || !t.focused) continue
            return root.sameApp(c, t)
        }
        return false
    }
    // a pid alone is not one app: on niri every X11 window reports xwayland-satellite's, so two X11 apps matched
    // and a click on one's notification raised nothing while the other had focus
    function sameApp(a, b): bool {
        if (!a || !b) return false
        const classesAgree = !a.cls || !b.cls || a.cls === b.cls
        return (a.pid > 0 && b.pid === a.pid && classesAgree) || (!!a.cls && b.cls === a.cls)
    }

    property var _pendingSource: null
    // only the default action stands for "show me the app": a button's click follows a raise and never guesses a window
    property bool _guessSource: false
    property var _urgentAtClick: []
    property string _focusAtClick: ""

    function _focusKey(): string {
        const here = root._hereWorkspace()
        // an empty workspace has no toplevel, and a named workspace may share another workspace's numeric ref
        return JSON.stringify([Compositor.activeToplevel?.ref ?? null, Compositor.focusedMonitor,
            here.ref, here.ref < 0 ? here.name : ""])
    }

    function _fallbackSource(source, clients, focusBefore: string, focusNow: string): var {
        if (!source || focusBefore !== focusNow || root.focusIsSourceApp(source, clients)) return null
        // resolve the saved handle again so a move or close while the action ran cannot focus stale data
        return (clients || []).find(c => c && c.wsId !== -1 && c.ref === source.ref
            && c.pid === source.pid && c.cls === source.cls) ?? null
    }

    readonly property Timer _sourceFallback: Timer {
        interval: 250
        onTriggered: {
            const source = root._pendingSource
            root._pendingSource = null
            if (!root._guessSource) return
            const c = root._fallbackSource(source, Compositor.toplevels, root._focusAtClick, root._focusKey())
            if (c) Compositor.focusToplevel(c)
        }
    }

    // hyprland marks a window urgent when its app asks to be raised and may not take focus: the exact window, even when nothing matched
    function raisedSource(toplevels, urgentRefs, before, source): var {
        const list = toplevels || []
        for (let i = 0; i < list.length; i++) {
            const t = list[i]
            if (!t || urgentRefs.indexOf(t.ref) < 0 || before.indexOf(t.ref) >= 0) continue
            // with the sender's app known, a window of another app pinging in the same quarter second is not it
            if (source && !root.sameApp(source, t)) continue
            return t
        }
        return null
    }
    Connections {
        target: Compositor
        enabled: root._sourceFallback.running
        function onUrgentRefsChanged() {
            if (root._focusAtClick !== root._focusKey()) return
            const t = root.raisedSource(Compositor.toplevels, Compositor.urgentRefs, root._urgentAtClick, root._pendingSource)
            if (!t) return
            root._sourceFallback.stop()
            root._pendingSource = null
            Compositor.focusToplevel(t)
        }
    }

    function _watchRaise(source, guess: bool): void {
        root._pendingSource = source
        root._guessSource = guess
        root._urgentAtClick = Compositor.urgentRefs
        root._focusAtClick = root._focusKey()
        root._sourceFallback.restart()
    }

    // a button's click too: with the sender known, another app's window turning urgent in the same quarter second took the focus
    function followRaise(notification): void {
        root._watchRaise(root._matchNotificationClient(notification, true), false)
    }

    function focusNotificationSourceAfterAction(notification): void {
        root._watchRaise(root._matchNotificationClient(notification, true), true)
    }

    function notificationSourceWorkspace(notification): int {
        return root.notificationSource(notification)?.wsId ?? -1
    }

    // niri numbers workspaces per output, so a workspace id alone names one on every monitor
    function notificationSource(notification): var {
        const c = root._matchNotificationClient(notification, false)
        return c ? { wsId: c.wsId ?? -1, output: String(c.output ?? "") } : null
    }

    // a class names the player's own window and a title only mentions it: a browser tab titled "Spotify", used
    // more recently, took the media card's click from the Spotify app. A player that can raise itself skips titles
    function mediaPlayerSource(clients, playerName: string, songTitle: string, here = root._hereWorkspace(), titles = true): var {
        const name   = String(playerName || "").toLowerCase()
        const norm   = (s) => String(s || "").toLowerCase()
        const browserName = root._browserClasses.some(b => root._hasBrowserToken(name, b))
        const pick = matches => root._chooseMatchingSource(clients, matches, here)

        let best = name.length > 0
            ? pick(c =>
                (browserName
                    ? root._browserClasses.some(b => root._hasBrowserToken(name, b)
                        && (root._hasBrowserToken(c.cls, b)
                            || root._hasBrowserToken(c.initialClass, b)))
                    : norm(c.cls).includes(name) || norm(c.initialClass).includes(name)))
            : null

        if (!best && titles && name.length > 0 && !browserName)
            best = pick(c => norm(c.title).includes(name))

        if (!best && browserName)
            best = pick(c =>
                root._browserClasses.some(b =>
                    root._hasBrowserToken(c.cls, b)
                    || root._hasBrowserToken(c.initialClass, b)))

        if (!best && titles && songTitle && songTitle.length > 4) {
            const t = songTitle.toLowerCase()
            best = pick(c => norm(c.title).includes(t))
        }
        return best
    }

    function focusMediaPlayer(playerName: string, songTitle: string, titles: bool): bool {
        const clients = root._clients()
        if (clients.length === 0) return false
        const best = root.mediaPlayerSource(clients, playerName, songTitle, root._hereWorkspace(), titles)
        if (best) Compositor.focusToplevel(best)
        return !!best
    }

    function focusTrayItem(id: string, title: string, tooltip: string): bool {
        const clients = root._clients()
        if (clients.length === 0) return false

        const hints = [id, title, tooltip].filter(s => s && String(s).length > 0)
        let best = null

        for (let i = 0; i < hints.length && !best; i++)
            best = root._chooseMatchingSource(clients, c =>
                root._classMatches(c, hints[i]) || root._appMatches(c, hints[i]))

        for (let i = 0; i < hints.length && !best; i++)
            best = root._resolveByDesktopEntry(clients, hints[i])

        if (best) {
            Compositor.focusToplevel(best)
            return true
        }
        return false
    }
}
