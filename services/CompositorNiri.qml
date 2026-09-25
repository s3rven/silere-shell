pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "NiriEvents.js" as NiriEvents

QtObject {
    id: root

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    readonly property string socketPath: String(Quickshell.env("NIRI_SOCKET") || "")

    property var _wsRaw: []
    property var _winRaw: []
    property int _titleTick: 0
    property int _activeTitleTick: 0
    property bool _overview: false
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    function _identity(value): string {
        return SafeText.singleLineText(value, Compositor.maxWindowIdentityChars)
    }

    function _title(value): string {
        return Compositor.windowTitle(value)
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

    function moveWorkspaceCommand(wsId, output, windowId, windowOutput): var {
        const targetOutput = String(output || "")
        const sourceOutput = String(windowOutput || "")
        const id = String(windowId)
        if (targetOutput.length > 0 && targetOutput !== sourceOutput) {
            // numeric workspace refs are per-output, so land the window on the clicked output first
            return ["sh", "-c",
                "niri msg action move-window-to-monitor --id \"$1\" \"$2\" "
                    + "&& niri msg action move-window-to-workspace "
                    + "--window-id \"$1\" --focus false \"$3\"",
                "sh", id, targetOutput, String(wsId)]
        }
        return ["niri", "msg", "action", "move-window-to-workspace",
            "--window-id", id, "--focus", "false", String(wsId)]
    }

    function moveActiveToWorkspace(wsId, output): void {
        const active = root.activeToplevel
        if (!active || active.ref === undefined || active.ref === null) return
        Quickshell.execDetached(root.moveWorkspaceCommand(
            wsId, output, active.ref, active.output))
    }

    function focusToplevel(c): void {
        if (c.ref) root._action(["focus-window", "--id", String(c.ref)])
    }

    function refreshToplevels(): void {
    }

    function _action(args): void {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args))
    }

    // niri sends WindowOpenedOrChanged for title-only updates too: publish at most one
    // focused tick per interval, and batch the off-screen titles nothing paints
    property Timer _titleSyncTimer: Timer {
        id: _titleSync
        interval: 180
        onTriggered: root._activeTitleTick++
    }

    property Timer _backgroundTitleSyncTimer: Timer {
        id: _backgroundTitleSync
        interval: 1500
        onTriggered: root._titleTick++
    }

    property Connections _idleConn: Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) {
                _titleSync.stop()
                _backgroundTitleSync.stop()
            } else {
                root._titleTick++
                root._activeTitleTick++
            }
        }
    }

    property Connections _settingsConn: Connections {
        target: ShellSettings
        function onShowWindowTitleChanged(): void {
            _titleSync.stop()
            _backgroundTitleSync.stop()
            root._titleTick++
            root._activeTitleTick++
        }
    }

    readonly property bool overviewActive: root._overview
    readonly property var specialOutputs: []

    readonly property var workspaces: {
        const src = root._wsRaw
        // an active window is not occupancy: a workspace holding only unfocused windows
        // reports none, so count real windows the way the hyprland backend does
        const winCount = {}
        const wins = root._winRaw
        for (let i = 0; i < wins.length; i++) {
            const win = wins[i]
            if (!win) continue
            const home = win.workspace_id
            if (home !== null && home !== undefined)
                winCount[home] = (winCount[home] ?? 0) + 1
        }
        const out = []
        for (let i = 0; i < src.length; i++) {
            const w = src[i]
            if (!w) continue
            out.push({
                wsId: w.idx, name: w.name ?? "", output: w.output ?? "",
                active: !!w.is_active, urgent: !!w.is_urgent,
                occupied: (winCount[w.id] ?? 0) > 0,
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
        root._activeTitleTick
        const wins = root._winRaw
        const ws = root._wsRaw
        let focused = null
        for (let i = 0; i < wins.length; i++) {
            if (wins[i] && wins[i].is_focused) {
                focused = wins[i]
                break
            }
        }
        if (!focused) return null
        let home = null
        for (let i = 0; i < ws.length; i++)
            if (ws[i] && ws[i].id === focused.workspace_id) { home = ws[i]; break }
        const app = root._identity(focused.app_id)
        return {
            appId: app, title: root._title(focused.title),
            cls: app, initialClass: app,
            pid: focused.pid ?? -1, ref: focused.id,
            wsRef: focused.workspace_id, wsId: home ? home.idx : -1,
            output: home ? (home.output ?? "") : "",
            focused: true,
            focusRank: focused.focus_timestamp
                ? -(Number(focused.focus_timestamp.secs ?? 0)
                    + Number(focused.focus_timestamp.nanos ?? 0) / 1e9)
                : 9999,
            fullscreen: !!focused.is_fullscreen
        }
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

    function _boundedWindows(incoming): var {
        const wins = []
        if (!Array.isArray(incoming)) return wins
        for (let i = 0; i < incoming.length; i++) {
            const bounded = root._boundedWindow(incoming[i])
            if (bounded) wins.push(bounded)
        }
        return wins
    }

    function _armTitleSync(focused: bool): void {
        if (!root._liveTitlesWanted || Idle.isIdle) return
        const timer = focused ? _titleSync : _backgroundTitleSync
        if (!timer.running) timer.start()
    }

    // a title-only change edits the row in place: rebuilding the list for every keystroke
    // in a browser address bar wakes every consumer of the window model
    function _applyWindowOpenedOrChanged(w): void {
        const current = root._winRaw
        const at = NiriEvents.indexOfWindow(current, w.id)
        if (at >= 0 && !root._windowChanged(current[at], w)) {
            const titleChanged = current[at].title !== w.title
            current[at].title = w.title
            if (titleChanged) root._armTitleSync(w.is_focused)
            return
        }
        root._winRaw = NiriEvents.windowsWithUpsert(current, w)
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
            const next = NiriEvents.workspacesWithActivated(root._wsRaw,
                ev.WorkspaceActivated.id, !!ev.WorkspaceActivated.focused)
            root._wsRaw = next.workspaces
            root.workspaceActivated(next.output)
            return
        }
        if (ev.WorkspaceUrgencyChanged) {
            const d = ev.WorkspaceUrgencyChanged
            root._wsRaw = NiriEvents.workspacesWithUrgency(root._wsRaw, d.id, !!d.urgent)
            return
        }
        if (ev.WindowsChanged) {
            root._winRaw = root._boundedWindows(ev.WindowsChanged.windows)
            return
        }
        if (ev.WindowOpenedOrChanged) {
            const w = root._boundedWindow(ev.WindowOpenedOrChanged.window)
            if (w) root._applyWindowOpenedOrChanged(w)
            return
        }
        if (ev.WindowClosed) {
            root._winRaw = NiriEvents.windowsWithout(root._winRaw, ev.WindowClosed.id)
            return
        }
        if (ev.WindowFocusChanged) {
            root._winRaw = NiriEvents.windowsWithFocus(root._winRaw, ev.WindowFocusChanged.id)
            return
        }
        if (ev.WindowFocusTimestampChanged) {
            const d = ev.WindowFocusTimestampChanged
            root._winRaw = NiriEvents.windowsWithFocusStamp(root._winRaw, d.id, d.focus_timestamp)
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
