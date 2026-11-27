pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "NiriEvents.js" as NiriEvents

QtObject {
    id: root

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)
    signal sharingState(bool active)
    signal screenshotTaken(string path)
    property bool sharingSupported: false
    property var _castIds: []
    property var _keyboardNames: []
    property int _keyboardIndex: 0
    readonly property string keyboardLayout: SafeText.singleLineText(root._keyboardNames[root._keyboardIndex] || "", 128)
    readonly property int keyboardLayoutCount: root._keyboardNames.length
    function cycleKeyboardLayout(): void {
        root._sendAction({ SwitchLayout: { layout: "Next" } })
    }

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

    // the bar shows per-output indexes. niri's JSON socket can address the workspace
    // by id in one action, even if focus moves or the index changes before it runs
    function _workspaceRef(wsId, output): var {
        const target = output || root.focusedMonitor
        if (!target) return null
        const workspace = root._wsRaw.find(w => w && w.idx === wsId && w.output === target)
        return workspace ? { Id: workspace.id } : null
    }

    function focusWorkspace(wsId, output): void {
        const reference = root._workspaceRef(wsId, output)
        if (reference) root._sendAction({ FocusWorkspace: { reference } })
    }

    function moveActiveToWorkspace(wsId, output): void {
        const active = root.activeToplevel
        if (!active || active.ref === undefined || active.ref === null) return
        const reference = root._workspaceRef(wsId, output)
        if (reference) root._sendAction({ MoveWindowToWorkspace: {
            window_id: active.ref, reference, focus: false
        } })
    }

    function _sendAction(action): void {
        if (root.socketPath.length > 0)
            _actionRequest.createObject(root, { message: JSON.stringify({ Action: action }) + "\n" })
    }

    // the event stream owns its socket. each request gets one reply on its own connection
    property Component _actionSocket: Component {
        id: _actionRequest

        Socket {
            id: request

            required property string message
            path: root.socketPath
            Component.onCompleted: connected = true
            onConnectedChanged: {
                if (connected) {
                    write(message)
                    flush()
                }
            }
            onError: request.destroy()
            parser: SplitParser { onRead: request.destroy() }
            property Timer _deadline: Timer {
                interval: 3000
                running: true
                onTriggered: request.destroy()
            }
        }
    }

    function focusToplevel(c): void {
        if (c.ref) root._sendAction({ FocusWindow: { id: c.ref } })
    }

    function refreshToplevels(): void {
        // window actions match on titles; flush the title events a hidden title widget left coalesced
        root._titleTick++
        root._activeTitleTick++
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
    // niri hands a click outside a popup to whatever is under it, so popups keep their full-screen dismiss windows
    readonly property Component popupGrab: null
    readonly property var specialOutputs: []

    readonly property var workspaces: {
        const src = root._wsRaw
        // an active window is not occupancy: a workspace holding only unfocused windows reports none, so count real windows the way the hyprland backend does
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
            // ref: the bar's urgent arrow matches urgentRefs against these
            out.push({
                appId: root._identity(w.app_id),
                wsId: home ? home.idx : -1,
                output: home ? (home.output ?? "") : "",
                ref: w.id
            })
        }
        return out
    }

    readonly property var urgentRefs: root._winRaw.filter(w => w && w.is_urgent).map(w => w.id)

    readonly property var toplevels: {
        void root._titleTick
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
                    : 9999
            })
        }
        return out
    }

    readonly property var activeToplevel: {
        void root._activeTitleTick
        const wins = root._winRaw
        const ws = root._wsRaw
        let focused = null
        for (let i = 0; i < wins.length; i++) {
            if (wins[i] && wins[i].is_focused) {
                focused = wins[i]
                break
            }
        }
        // a layer surface holding the keyboard (a Silere popup, a launcher) leaves no window focused: the focused
        // workspace's active window is still the one in front, as Hyprland keeps reporting it, so the title stays
        if (!focused) {
            const front = ws.find(w => w && w.is_focused)
            const id = front ? front.active_window_id ?? null : null
            if (id !== null) focused = wins.find(w => w && w.id === id) || null
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
                : 9999
        }
    }

    // niri's IPC has no fullscreen field; foreign-toplevel carries it, activated only on the focused window
    readonly property bool activeFullscreen: {
        const list = ToplevelManager.toplevels.values
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].activated && list[i].fullscreen) return true
        return false
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
            || previous.is_urgent !== next.is_urgent
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
            is_urgent: !!raw.is_urgent,
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

    // a title-only change edits the row in place: rebuilding the list for every keystroke in a browser address bar wakes every consumer of the window model
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

        if (ev.KeyboardLayoutsChanged) {
            const layouts = ev.KeyboardLayoutsChanged.keyboard_layouts || {}
            root._keyboardNames = Array.isArray(layouts.names) ? layouts.names : []
            root._keyboardIndex = Number(layouts.current_idx || 0)
            return
        }
        if (ev.KeyboardLayoutSwitched) {
            root._keyboardIndex = Number(ev.KeyboardLayoutSwitched.idx || 0)
            return
        }
        if (ev.CastsChanged) {
            root.sharingSupported = true
            root._castIds = (ev.CastsChanged.casts || []).map(c => String(c.stream_id))
            root.sharingState(root._castIds.length > 0)
            return
        }
        if (ev.CastStartedOrChanged && ev.CastStartedOrChanged.cast) {
            root.sharingSupported = true
            const id = String(ev.CastStartedOrChanged.cast.stream_id)
            if (root._castIds.indexOf(id) < 0) root._castIds = root._castIds.concat([id])
            root.sharingState(root._castIds.length > 0)
            return
        }
        if (ev.CastStopped) {
            root._castIds = root._castIds.filter(id => id !== String(ev.CastStopped.stream_id))
            root.sharingState(root._castIds.length > 0)
            return
        }

        if (ev.WorkspacesChanged) {
            const next = ev.WorkspacesChanged.workspaces || []
            const changedOutput = NiriEvents.focusedWorkspaceChangeOutput(root._wsRaw, next)
            root._wsRaw = next
            if (changedOutput !== null) root.workspaceActivated(changedOutput)
            return
        }
        if (ev.WorkspaceActivated) {
            const next = NiriEvents.workspacesWithActivated(root._wsRaw,
                ev.WorkspaceActivated.id, !!ev.WorkspaceActivated.focused)
            root._wsRaw = next.workspaces
            root.workspaceActivated(next.output)
            return
        }
        if (ev.WorkspaceActiveWindowChanged) {
            const d = ev.WorkspaceActiveWindowChanged
            root._wsRaw = NiriEvents.workspacesWithActiveWindow(root._wsRaw, d.workspace_id, d.active_window_id ?? null)
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
        // niri marks a window urgent where it refuses an activation (a token with no serial), as hyprland does
        if (ev.WindowUrgencyChanged) {
            const d = ev.WindowUrgencyChanged
            root._winRaw = NiriEvents.workspacesWithUrgency(root._winRaw, d.id, !!d.urgent)
            return
        }
        if (ev.WindowFocusTimestampChanged) {
            const d = ev.WindowFocusTimestampChanged
            root._winRaw = NiriEvents.windowsWithFocusStamp(root._winRaw, d.id, d.focus_timestamp)
            return
        }
        if (ev.ScreenshotCaptured) {
            root.screenshotTaken(String(ev.ScreenshotCaptured.path ?? ""))
            return
        }
        if (ev.OverviewOpenedOrClosed) {
            root._overview = !!ev.OverviewOpenedOrClosed.is_open
            return
        }
    }

    function _resetDisconnectedState(): void {
        _titleSync.stop()
        _backgroundTitleSync.stop()
        root._overview = false
        root._winRaw = []
        root._wsRaw = []
        root._castIds = []
        root._keyboardNames = []
        root.sharingSupported = false
        // keep the last sharing decision until a fresh snapshot confirms that casts stopped
    }

    // Socket.connected is both the current state and the connect request. A
    // compositor restart drops it to false, so retry until the replacement
    // niri socket accepts the event stream again
    property int _reconnectFailures: 0
    property Timer _reconnectTimer: Timer {
        id: _reconnect
        interval: Math.min(30000, 1500 * Math.pow(2, root._reconnectFailures))
        repeat: true
        running: root.socketPath.length > 0 && !_socket.connected
        onTriggered: {
            root._reconnectFailures = Math.min(5, root._reconnectFailures + 1)
            _socket.connected = true
        }
    }

    // Quickshell leaves ShellScreen.serialNumber empty on wayland (quickshell#903); niri's output list has the EDID
    // serial, so bar and popup display choices follow the monitor rather than the port. niri's event stream says
    // nothing about outputs, so the list is read when Quickshell's screens change
    property var monitorSerials: ({})
    function serialsFrom(text: string): var {
        let outputs = null
        try { outputs = JSON.parse(text) } catch (e) { return ({}) }
        const out = {}
        if (!outputs || typeof outputs !== "object" || Array.isArray(outputs)) return out
        for (const key in outputs) {
            const o = outputs[key]
            const name = o ? o.name : undefined
            const serial = o ? o.serial : undefined
            if (typeof name === "string" && typeof serial === "string" && serial.trim().length > 0)
                out[name] = serial.trim()
        }
        return out
    }
    // the output's own scale: a ShellScreen reports Qt's rounded-up buffer ratio, 2 on a 1.25 output
    property var monitorScales: ({})
    function scalesFrom(text: string): var {
        let outputs = null
        try { outputs = JSON.parse(text) } catch (e) { return ({}) }
        const out = {}
        if (!outputs || typeof outputs !== "object" || Array.isArray(outputs)) return out
        for (const key in outputs) {
            const o = outputs[key]
            const scale = o && o.logical ? Number(o.logical.scale) : NaN
            if (o && typeof o.name === "string" && isFinite(scale) && scale > 0) out[o.name] = scale
        }
        return out
    }
    function monitorScale(screen): real {
        return screen ? (root.monitorScales[screen.name] ?? 0) : 0
    }
    property bool _serialsAgain: false
    function _askSerials(): void {
        if (root.socketPath.length === 0) return
        if (_outputsProc.running) root._serialsAgain = true
        else _outputsProc.running = true
    }
    property BoundedProcess _outputsReader: BoundedProcess {
        id: _outputsProc
        command: ["niri", "msg", "--json", "outputs"]
        timeoutMs: 3000
        stdout: StdioCollector { id: _outputsOut }
        onExited: code => {
            if (_outputsProc.completedSuccessfully(code)) {
                const next = root.serialsFrom(_outputsOut.text)
                if (JSON.stringify(next) !== JSON.stringify(root.monitorSerials)) root.monitorSerials = next
                const scales = root.scalesFrom(_outputsOut.text)
                if (JSON.stringify(scales) !== JSON.stringify(root.monitorScales)) root.monitorScales = scales
            }
            if (root._serialsAgain) {
                root._serialsAgain = false
                Qt.callLater(root._askSerials)
            }
        }
    }
    property Connections _screensConn: Connections {
        target: Quickshell
        function onScreensChanged() { root._askSerials() }
    }
    Component.onCompleted: root._askSerials()

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
                root._reconnectFailures = 0
                write("\"EventStream\"\n")
                flush()
            } else {
                root._resetDisconnectedState()
                _reconnect.restart()
            }
        }
    }
}
