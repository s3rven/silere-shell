pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    readonly property string socketPath: String(Quickshell.env("NIRI_SOCKET") || "")

    property var _wsRaw: []
    property var _winRaw: []
    property int _titleTick: 0
    property bool _overview: false
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    function _identity(value): string {
        return SafeText.singleLineText(value, Compositor.maxWindowIdentityChars)
    }

    function _title(value): string {
        return SafeText.singleLineText(value, Compositor.maxWindowTitleChars)
    }

    function monitorName(screen): string {
        return screen.name
    }

    function focusWorkspace(wsId, output): void {
        // focus-workspace takes a per-output index, so the monitor switch must land first - chain both in one process
        if (output.length > 0 && output !== root.focusedMonitor)
            Quickshell.execDetached(["sh", "-c",
                "niri msg action focus-monitor \"$1\" && niri msg action focus-workspace \"$2\"",
                "sh", output, String(wsId)])
        else
            root._action(["focus-workspace", String(wsId)])
    }

    function moveActiveToWorkspace(wsId): void {
        root._action(["move-window-to-workspace", "--focus", "false", String(wsId)])
    }

    function focusToplevel(c): void {
        if (c.ref) root._action(["focus-window", "--id", String(c.ref)])
    }

    function refreshToplevels(): void {
    }

    function _action(args): void {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args))
    }

    // niri sends WindowOpenedOrChanged for title-only updates too: mutate now, publish at most one title list per interval
    property Timer _titleSyncTimer: Timer {
        id: _titleSync
        interval: 180
        onTriggered: root._titleTick++
    }

    property Connections _idleConn: Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) _titleSync.stop()
            else root._titleTick++
        }
    }

    property Connections _settingsConn: Connections {
        target: ShellSettings
        function onShowWindowTitleChanged(): void {
            _titleSync.stop()
            root._titleTick++
        }
    }

    readonly property bool overviewActive: root._overview
    readonly property string specialOutput: ""

    readonly property var workspaces: {
        const src = root._wsRaw
        const out = []
        for (let i = 0; i < src.length; i++) {
            const w = src[i]
            if (!w) continue
            out.push({
                wsId: w.idx, name: w.name ?? "", output: w.output ?? "",
                active: !!w.is_active, urgent: !!w.is_urgent,
                occupied: w.active_window_id !== null && w.active_window_id !== undefined,
                ref: w.id
            })
        }
        return out
    }

    readonly property var workspaceToplevels: {
        const wins = root._winRaw
        const ws = root._wsRaw
        const byId = {}
        for (let i = 0; i < ws.length; i++) if (ws[i]) byId[ws[i].id] = ws[i]
        const out = []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            if (!w) continue
            const home = byId[w.workspace_id] || null
            out.push({
                appId: root._identity(w.app_id),
                wsId: home ? home.idx : -1,
                output: home ? (home.output ?? "") : ""
            })
        }
        return out
    }

    readonly property var toplevels: {
        root._titleTick
        const wins = root._winRaw
        const ws = root._wsRaw
        const byId = {}
        for (let i = 0; i < ws.length; i++) if (ws[i]) byId[ws[i].id] = ws[i]
        const out = []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            if (!w) continue
            const home = byId[w.workspace_id] || null
            const app = root._identity(w.app_id)
            out.push({
                appId: app, title: root._title(w.title),
                cls: app, initialClass: app,
                pid: w.pid ?? -1, ref: w.id,
                wsRef: w.workspace_id, wsId: home ? home.idx : -1,
                output: home ? (home.output ?? "") : "",
                focused: !!w.is_focused,
                focusRank: w.focus_timestamp
                    ? -(Number(w.focus_timestamp.secs ?? 0) + Number(w.focus_timestamp.nanos ?? 0) / 1e9)
                    : 9999,
                fullscreen: !!w.is_fullscreen
            })
        }
        return out
    }

    readonly property var activeToplevel: {
        const t = root.toplevels
        for (let i = 0; i < t.length; i++) if (t[i].focused) return t[i]
        return null
    }

    readonly property string focusedMonitor: {
        const ws = root._wsRaw
        for (let i = 0; i < ws.length; i++)
            if (ws[i] && ws[i].is_focused) return ws[i].output ?? ""
        return ""
    }

    readonly property int focusedWorkspaceRef: {
        const ws = root._wsRaw
        for (let i = 0; i < ws.length; i++)
            if (ws[i] && ws[i].is_focused) return ws[i].id
        return -1
    }

    function _windowChanged(previous, next): bool {
        if (!previous || !next) return true
        const oldStamp = previous.focus_timestamp || {}
        const newStamp = next.focus_timestamp || {}
        return previous.app_id !== next.app_id
            || previous.pid !== next.pid
            || previous.workspace_id !== next.workspace_id
            || previous.is_focused !== next.is_focused
            || previous.is_fullscreen !== next.is_fullscreen
            || oldStamp.secs !== newStamp.secs
            || oldStamp.nanos !== newStamp.nanos
    }

    function _boundedWindow(raw): var {
        if (!raw || typeof raw !== "object") return null
        const stamp = raw.focus_timestamp || {}
        return {
            id: raw.id,
            app_id: root._identity(raw.app_id),
            title: root._title(raw.title),
            pid: raw.pid ?? -1,
            workspace_id: raw.workspace_id,
            is_focused: !!raw.is_focused,
            is_fullscreen: !!raw.is_fullscreen,
            focus_timestamp: raw.focus_timestamp ? {
                secs: Number(stamp.secs ?? 0),
                nanos: Number(stamp.nanos ?? 0)
            } : null
        }
    }

    function _onLine(line): void {
        const text = String(line || "").trim()
        if (text.length === 0 || text.charAt(0) !== "{") return
        let ev
        try { ev = JSON.parse(text) } catch (e) { return }

        if (ev.WorkspacesChanged) {
            root._wsRaw = ev.WorkspacesChanged.workspaces || []
            root.workspaceActivated(root.focusedMonitor)
            return
        }
        if (ev.WorkspaceActivated) {
            const id = ev.WorkspaceActivated.id
            const focused = !!ev.WorkspaceActivated.focused
            const src = root._wsRaw
            let output = ""
            for (let i = 0; i < src.length; i++)
                if (src[i] && src[i].id === id) { output = src[i].output ?? ""; break }
            const ws = []
            for (let i = 0; i < src.length; i++) {
                const w = src[i]
                if (!w) { ws.push(w); continue }
                const patch = {}
                if (w.output === output) patch.is_active = w.id === id
                if (focused) patch.is_focused = w.id === id
                ws.push(Object.keys(patch).length ? Object.assign({}, w, patch) : w)
            }
            root._wsRaw = ws
            root.workspaceActivated(output)
            return
        }
        if (ev.WorkspaceActiveWindowChanged) {
            const d = ev.WorkspaceActiveWindowChanged
            const ws = root._wsRaw.slice()
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].id === d.workspace_id)
                    ws[i] = Object.assign({}, ws[i], { active_window_id: d.active_window_id })
            root._wsRaw = ws
            return
        }
        if (ev.WorkspaceUrgencyChanged) {
            const d = ev.WorkspaceUrgencyChanged
            const ws = root._wsRaw.slice()
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].id === d.id)
                    ws[i] = Object.assign({}, ws[i], { is_urgent: !!d.urgent })
            root._wsRaw = ws
            return
        }
        if (ev.WindowsChanged) {
            const incoming = Array.isArray(ev.WindowsChanged.windows)
                ? ev.WindowsChanged.windows : []
            const wins = []
            for (let i = 0; i < incoming.length; i++) {
                const bounded = root._boundedWindow(incoming[i])
                if (bounded) wins.push(bounded)
            }
            root._winRaw = wins
            return
        }
        if (ev.WindowOpenedOrChanged) {
            const w = root._boundedWindow(ev.WindowOpenedOrChanged.window)
            if (!w) return
            const current = root._winRaw
            let foundAt = -1
            for (let i = 0; i < current.length; i++)
                if (current[i] && current[i].id === w.id) { foundAt = i; break }
            if (foundAt >= 0 && !root._windowChanged(current[foundAt], w)) {
                const titleChanged = current[foundAt].title !== w.title
                current[foundAt].title = w.title
                if (titleChanged && root._liveTitlesWanted && !Idle.isIdle
                        && !_titleSync.running)
                    _titleSync.start()
                return
            }

            const wins = current.slice()
            for (let i = 0; i < wins.length; i++) {
                if (wins[i] && wins[i].id === w.id) wins[i] = w
                else if (wins[i] && w.is_focused) wins[i] = Object.assign({}, wins[i], { is_focused: false })
            }
            if (foundAt < 0) wins.push(w)
            root._winRaw = wins
            return
        }
        if (ev.WindowClosed) {
            const id = ev.WindowClosed.id
            root._winRaw = root._winRaw.filter(w => w && w.id !== id)
            return
        }
        if (ev.WindowFocusChanged) {
            const id = ev.WindowFocusChanged.id
            const wins = root._winRaw.slice()
            for (let i = 0; i < wins.length; i++)
                if (wins[i]) wins[i] = Object.assign({}, wins[i], { is_focused: wins[i].id === id })
            root._winRaw = wins
            return
        }
        if (ev.WindowFocusTimestampChanged) {
            const d = ev.WindowFocusTimestampChanged
            const wins = root._winRaw.slice()
            for (let i = 0; i < wins.length; i++)
                if (wins[i] && wins[i].id === d.id)
                    wins[i] = Object.assign({}, wins[i], { focus_timestamp: d.focus_timestamp })
            root._winRaw = wins
            return
        }
        if (ev.OverviewOpenedOrClosed) {
            root._overview = !!ev.OverviewOpenedOrClosed.is_open
            return
        }
    }

    // Socket.connected is both the current state and the connect request. A
    // compositor restart drops it to false, so retry until the replacement
    // niri socket accepts the event stream again.
    property Timer _reconnectTimer: Timer {
        id: _reconnect
        interval: 1500
        repeat: true
        running: !_socket.connected
        onTriggered: _socket.connected = true
    }

    property Socket _eventSocket: Socket {
        id: _socket
        path: root.socketPath
        connected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root._onLine(line)
        }
        Component.onCompleted: connected = true
        onConnectedChanged: {
            if (connected) {
                write("\"EventStream\"\n")
                flush()
            } else {
                _reconnect.restart()
            }
        }
    }
}
