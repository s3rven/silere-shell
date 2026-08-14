pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property int maxWindowIdentityChars: 512
    readonly property int maxWindowTitleChars: 2048

    function _windowIdentity(value): string {
        return SafeText.singleLineText(value, root.maxWindowIdentityChars)
    }

    function _windowTitle(value): string {
        return SafeText.singleLineText(value, root.maxWindowTitleChars)
    }

    readonly property string _niriSock: String(Quickshell.env("NIRI_SOCKET") || "")
    readonly property bool isNiri:     _niriSock.length > 0
    readonly property bool isHyprland: !isNiri

    readonly property bool hasSpecialWorkspaces: isHyprland

    readonly property var workspaces:     isNiri ? _niriWorkspaces : _hyprWorkspaces
    readonly property var toplevels:      isNiri ? _niriToplevels : _hyprToplevels
    // off the live title path: an animated title would wake every bar per frame
    readonly property var workspaceToplevels: isNiri ? _niriWorkspaceToplevels : _hyprBaseToplevels
    readonly property var activeToplevel: isNiri ? _niriActive : _hyprActive
    readonly property string focusedMonitor: isNiri ? _niriFocusedMon : _hyprFocusedMon
    readonly property int focusedWorkspaceRef: {
        if (root.isNiri) {
            const ws = root._niriWsRaw
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].is_focused) return ws[i].id
            return -1
        }
        root._hyprLayoutTick
        return Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id ?? -1) : -1
    }
    readonly property bool overviewActive:   isNiri ? _niriOverview : _hyprOverview
    readonly property bool activeFullscreen:  !!(activeToplevel && activeToplevel.fullscreen)
    readonly property string specialOutput:  isNiri ? "" : _hyprSpecial

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    function monitorName(screen): string {
        if (!screen) return ""
        if (root.isNiri) return screen.name
        const m = Hyprland.monitorFor(screen)
        return m ? m.name : ""
    }

    function activeWorkspaceId(output): int {
        const ws = root.workspaces
        for (let i = 0; i < ws.length; i++)
            if (ws[i].output === output && ws[i].active) return ws[i].wsId
        return -1
    }

    function focusWorkspace(wsId, output): void {
        if (wsId === undefined || wsId === null || wsId < 0) return
        const mon = output || ""
        if (root.isNiri) {
            // focus-workspace takes a per-output index, so the monitor switch must land first - chain both in one process
            if (mon.length > 0 && mon !== root._niriFocusedMon)
                Quickshell.execDetached(["sh", "-c",
                    "niri msg action focus-monitor \"$1\" && niri msg action focus-workspace \"$2\"",
                    "sh", mon, String(wsId)])
            else
                root._niriAction(["focus-workspace", String(wsId)])
            return
        }
        if (mon.length > 0) HyprDispatch.dispatchPair("focusmonitor", mon, "workspace", wsId)
        else HyprDispatch.dispatch("workspace", wsId)
    }

    function moveActiveToWorkspace(wsId): void {
        if (wsId === undefined || wsId === null || wsId < 1) return
        if (root.isNiri) {
            root._niriAction(["move-window-to-workspace", "--focus", "false", String(wsId)])
            return
        }
        HyprDispatch.dispatch("movetoworkspacesilent", wsId)
    }

    function focusToplevel(c): void {
        if (!c) return
        if (root.isNiri) {
            if (c.ref) root._niriAction(["focus-window", "--id", String(c.ref)])
            return
        }
        const hasWs = c.wsRef !== undefined && c.wsRef !== null && c.wsRef >= 0
        const addr = c.ref
            ? (String(c.ref).startsWith("address:") ? String(c.ref) : "address:" + c.ref) : ""
        if (hasWs && addr.length > 0) HyprDispatch.dispatchPair("workspace", c.wsRef, "focuswindow", addr)
        else if (hasWs) HyprDispatch.dispatch("workspace", c.wsRef)
        else if (addr.length > 0) HyprDispatch.dispatch("focuswindow", addr)
    }

    property int _hyprLayoutTick: 0
    property var _hyprLiveTitles: ({})
    property bool _hyprRefreshAgain: false
    property string _hyprActiveAddr: ""
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    function refreshToplevels(): void {
        if (!root.isHyprland) return
        if (_hyprRefreshSettle.running) {
            root._hyprRefreshAgain = true
            return
        }
        Hyprland.refreshToplevels()
        _hyprRefreshSettle.restart()
    }

    function _syncHyprLiveTitles(): void {
        if (!root.isHyprland || !root._liveTitlesWanted) return
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const next = {}
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const c = t ? t.lastIpcObject : null
            if (!c || !c.address) continue
            next[c.address] = root._windowTitle(t.title || c.title)
        }

        const oldKeys = Object.keys(root._hyprLiveTitles)
        const nextKeys = Object.keys(next)
        if (oldKeys.length === nextKeys.length
                && nextKeys.every(key => root._hyprLiveTitles[key] === next[key])) return
        root._hyprLiveTitles = next
    }

    Timer {
        id: _hyprRefreshSettle
        interval: 80
        onTriggered: {
            root._hyprLayoutTick++
            root._syncHyprLiveTitles()
            if (!root._hyprRefreshAgain) return
            root._hyprRefreshAgain = false
            Hyprland.refreshToplevels()
            restart()
        }
    }

    // hyprland fires windowtitle and windowtitlev2 per title frame; coalesce the pair
    Timer {
        id: _hyprTitleSync
        interval: 180
        onTriggered: root._syncHyprLiveTitles()
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) {
                _hyprTitleSync.stop()
                _niriTitleSync.stop()
            } else if (root.isNiri) {
                root._niriTitleTick++
            } else {
                root._syncHyprLiveTitles()
            }
        }
    }

    Connections {
        target: ShellSettings
        function onWsShowAppIconsChanged(): void {
            if (ShellSettings.wsShowAppIcons) root.refreshToplevels()
        }
        function onShowWindowTitleChanged(): void {
            if (root.isNiri) {
                _niriTitleSync.stop()
                root._niriTitleTick++
                return
            }
            if (ShellSettings.showWindowTitle) {
                root.refreshToplevels()
                root._syncHyprLiveTitles()
            } else {
                _hyprTitleSync.stop()
                root._hyprLiveTitles = ({})
            }
        }
    }

    readonly property string _hyprFocusedMon: {
        root._hyprLayoutTick
        return Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name ?? "") : ""
    }

    readonly property var _hyprWorkspaces: {
        root._hyprLayoutTick
        if (root.isNiri) return []
        const mons = Hyprland.monitors ? (Hyprland.monitors.values ?? []) : []
        const activeByOutput = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            if (m && m.name && m.activeWorkspace) activeByOutput[m.name] = m.activeWorkspace.id
        }
        // hyprland keeps a workspace object alive after its last window closes, so existence is
        // not occupancy; count real toplevels or an emptied workspace stays lit like a full one
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const winCount = {}
        for (let i = 0; i < tops.length; i++) {
            const c = tops[i] ? tops[i].lastIpcObject : null
            if (!c || !c.address) continue
            const id = c.workspace ? (c.workspace.id ?? -1) : -1
            if (id > 0) winCount[id] = (winCount[id] ?? 0) + 1
        }
        const vals = Hyprland.workspaces ? (Hyprland.workspaces.values ?? []) : []
        const out = []
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (!ws) continue
            const output = ws.monitor ? (ws.monitor.name ?? "") : ""
            out.push({
                wsId: ws.id, name: ws.name ?? "", output: output,
                active: activeByOutput[output] === ws.id,
                urgent: ws.urgent ?? false,
                occupied: (winCount[ws.id] ?? 0) > 0, ref: ws.id
            })
        }
        return out
    }

    // shared layout base built once; the title-facing list below only overlays the sampled strings
    readonly property var _hyprBaseToplevels: {
        root._hyprLayoutTick
        if (root.isNiri) return []
        const wsOut = {}
        const wsVals = Hyprland.workspaces ? (Hyprland.workspaces.values ?? []) : []
        for (let i = 0; i < wsVals.length; i++) {
            const ws = wsVals[i]
            if (ws) wsOut[ws.id] = ws.monitor ? (ws.monitor.name ?? "") : ""
        }
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const out = []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const c = t ? t.lastIpcObject : null
            if (!c || !c.address) continue
            const wsId = c.workspace ? (c.workspace.id ?? -1) : -1
            out.push({
                appId: root._windowIdentity((t.wayland && t.wayland.appId)
                    || c.class || c.initialClass),
                title: root._windowTitle(c.title),
                cls: root._windowIdentity(c.class),
                initialClass: root._windowIdentity(c.initialClass),
                pid: c.pid ?? -1, ref: c.address,
                wsRef: wsId, wsId: wsId, output: wsOut[wsId] ?? "",
                focused: !!(Hyprland.activeToplevel && Hyprland.activeToplevel === t),
                focusRank: c.focusHistoryID ?? 9999,
                fullscreen: !!c.fullscreen
            })
        }
        return out
    }

    readonly property var _hyprToplevels: {
        const base = root._hyprBaseToplevels
        if (!root._liveTitlesWanted) return base
        const out = []
        for (let i = 0; i < base.length; i++) {
            const t = base[i]
            const liveTitle = root._hyprLiveTitles[t.ref]
            out.push({
                appId: t.appId,
                // titles are sampled by _hyprTitleSync; reading t.title here would subscribe this binding to every title frame
                title: liveTitle !== undefined ? liveTitle : t.title,
                cls: t.cls, initialClass: t.initialClass,
                pid: t.pid, ref: t.ref,
                wsRef: t.wsRef, wsId: t.wsId, output: t.output,
                focused: t.focused,
                focusRank: t.focusRank,
                fullscreen: t.fullscreen
            })
        }
        return out
    }

    readonly property var _hyprActive: {
        const t = Hyprland.activeToplevel
        if (!t) return null
        const tops = root._hyprToplevels
        const c = t.lastIpcObject
        const addr = c ? c.address : null
        for (let i = 0; i < tops.length; i++)
            if (addr && tops[i].ref === addr) return tops[i]
        return null
    }

    property bool _hyprOverview: false
    property string _hyprSpecial: ""

    function _updateSpecial(data): void {
        const parts = String(data ?? "").split(",")
        if (parts.length < 2) { root._hyprSpecial = ""; return }
        root._hyprSpecial = String(parts[parts.length - 2]).length > 0
            ? String(parts[parts.length - 1]) : ""
    }

    Connections {
        target: Hyprland
        enabled: root.isHyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "windowtitle" || n === "windowtitlev2" || n === "activewindow") {
                if (root._liveTitlesWanted && !Idle.isIdle && !_hyprTitleSync.running)
                    _hyprTitleSync.start()
                return
            }
            // the shell's own popups, OSD and notifications each fire openlayer/closelayer, and
            // none of these touch the workspace, monitor or toplevel lists the models read.
            // changefloatingmode is inert for the same reason: the toplevel model carries no
            // floating state, and it fired 420 times in two hours of ordinary use
            if (n === "openlayer" || n === "closelayer" || n === "submap"
                    || n === "activelayout" || n === "screencast"
                    || n === "changefloatingmode")
                return
            // activewindow refires per title frame; only v2's address distinguishes a real focus change
            if (n === "activewindowv2") {
                const addr = String(event.data ?? "")
                if (addr === root._hyprActiveAddr) {
                    if (root._liveTitlesWanted && !Idle.isIdle && !_hyprTitleSync.running)
                        _hyprTitleSync.start()
                    return
                }
                root._hyprActiveAddr = addr
                root.refreshToplevels()
                root._hyprLayoutTick++
                return
            }
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
                || n === "fullscreen")
                root.refreshToplevels()
            if (n === "activespecial" || n === "activespecialv2")
                root._updateSpecial(event.data)
            if (n === "scrolloverview")
                root.overviewRaw(event.data === "1")
            if (n === "workspace" || n === "workspacev2" || n === "focusedmon"
                || n === "focusedmonv2" || n === "activemon")
                root.workspaceActivated(root._hyprFocusedMon)
            root._hyprLayoutTick++
        }
    }

    property var _niriWsRaw: []
    property var _niriWinRaw: []
    property bool _niriOverview: false
    property int _niriTitleTick: 0

    // niri sends WindowOpenedOrChanged for title-only updates too: mutate now, publish at most one title list per interval
    Timer {
        id: _niriTitleSync
        interval: 180
        onTriggered: root._niriTitleTick++
    }

    readonly property var _niriWorkspaces: {
        const src = root._niriWsRaw
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

    readonly property var _niriWorkspaceToplevels: {
        const wins = root._niriWinRaw
        const ws = root._niriWsRaw
        const byId = {}
        for (let i = 0; i < ws.length; i++) if (ws[i]) byId[ws[i].id] = ws[i]
        const out = []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            if (!w) continue
            const home = byId[w.workspace_id] || null
            out.push({
                appId: root._windowIdentity(w.app_id),
                wsId: home ? home.idx : -1,
                output: home ? (home.output ?? "") : ""
            })
        }
        return out
    }

    readonly property var _niriToplevels: {
        root._niriTitleTick
        const wins = root._niriWinRaw
        const ws = root._niriWsRaw
        const byId = {}
        for (let i = 0; i < ws.length; i++) if (ws[i]) byId[ws[i].id] = ws[i]
        const out = []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            if (!w) continue
            const home = byId[w.workspace_id] || null
            const app = root._windowIdentity(w.app_id)
            out.push({
                appId: app, title: root._windowTitle(w.title),
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

    readonly property var _niriActive: {
        const t = root._niriToplevels
        for (let i = 0; i < t.length; i++) if (t[i].focused) return t[i]
        return null
    }

    readonly property string _niriFocusedMon: {
        const ws = root._niriWsRaw
        for (let i = 0; i < ws.length; i++)
            if (ws[i] && ws[i].is_focused) return ws[i].output ?? ""
        return ""
    }

    function _niriAction(args): void {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args))
    }

    function _niriWindowChanged(previous, next): bool {
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

    function _boundedNiriWindow(raw): var {
        if (!raw || typeof raw !== "object") return null
        const stamp = raw.focus_timestamp || {}
        return {
            id: raw.id,
            app_id: root._windowIdentity(raw.app_id),
            title: root._windowTitle(raw.title),
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

    function _onNiriLine(line): void {
        const text = String(line || "").trim()
        if (text.length === 0 || text.charAt(0) !== "{") return
        let ev
        try { ev = JSON.parse(text) } catch (e) { return }

        if (ev.WorkspacesChanged) {
            root._niriWsRaw = ev.WorkspacesChanged.workspaces || []
            root.workspaceActivated(root._niriFocusedMon)
            return
        }
        if (ev.WorkspaceActivated) {
            const id = ev.WorkspaceActivated.id
            const focused = !!ev.WorkspaceActivated.focused
            const src = root._niriWsRaw
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
            root._niriWsRaw = ws
            root.workspaceActivated(output)
            return
        }
        if (ev.WorkspaceActiveWindowChanged) {
            const d = ev.WorkspaceActiveWindowChanged
            const ws = root._niriWsRaw.slice()
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].id === d.workspace_id)
                    ws[i] = Object.assign({}, ws[i], { active_window_id: d.active_window_id })
            root._niriWsRaw = ws
            return
        }
        if (ev.WorkspaceUrgencyChanged) {
            const d = ev.WorkspaceUrgencyChanged
            const ws = root._niriWsRaw.slice()
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].id === d.id)
                    ws[i] = Object.assign({}, ws[i], { is_urgent: !!d.urgent })
            root._niriWsRaw = ws
            return
        }
        if (ev.WindowsChanged) {
            const incoming = Array.isArray(ev.WindowsChanged.windows)
                ? ev.WindowsChanged.windows : []
            const wins = []
            for (let i = 0; i < incoming.length; i++) {
                const bounded = root._boundedNiriWindow(incoming[i])
                if (bounded) wins.push(bounded)
            }
            root._niriWinRaw = wins
            return
        }
        if (ev.WindowOpenedOrChanged) {
            const w = root._boundedNiriWindow(ev.WindowOpenedOrChanged.window)
            if (!w) return
            const current = root._niriWinRaw
            let foundAt = -1
            for (let i = 0; i < current.length; i++)
                if (current[i] && current[i].id === w.id) { foundAt = i; break }
            if (foundAt >= 0 && !root._niriWindowChanged(current[foundAt], w)) {
                const titleChanged = current[foundAt].title !== w.title
                current[foundAt].title = w.title
                if (titleChanged && root._liveTitlesWanted && !Idle.isIdle
                        && !_niriTitleSync.running)
                    _niriTitleSync.start()
                return
            }

            const wins = current.slice()
            for (let i = 0; i < wins.length; i++) {
                if (wins[i] && wins[i].id === w.id) wins[i] = w
                else if (wins[i] && w.is_focused) wins[i] = Object.assign({}, wins[i], { is_focused: false })
            }
            if (foundAt < 0) wins.push(w)
            root._niriWinRaw = wins
            return
        }
        if (ev.WindowClosed) {
            const id = ev.WindowClosed.id
            root._niriWinRaw = root._niriWinRaw.filter(w => w && w.id !== id)
            return
        }
        if (ev.WindowFocusChanged) {
            const id = ev.WindowFocusChanged.id
            const wins = root._niriWinRaw.slice()
            for (let i = 0; i < wins.length; i++)
                if (wins[i]) wins[i] = Object.assign({}, wins[i], { is_focused: wins[i].id === id })
            root._niriWinRaw = wins
            return
        }
        if (ev.WindowFocusTimestampChanged) {
            const d = ev.WindowFocusTimestampChanged
            const wins = root._niriWinRaw.slice()
            for (let i = 0; i < wins.length; i++)
                if (wins[i] && wins[i].id === d.id)
                    wins[i] = Object.assign({}, wins[i], { focus_timestamp: d.focus_timestamp })
            root._niriWinRaw = wins
            return
        }
        if (ev.OverviewOpenedOrClosed) {
            root._niriOverview = !!ev.OverviewOpenedOrClosed.is_open
            return
        }
    }

    // Socket.connected is both the current state and the connect request. A
    // compositor restart drops it to false, so retry until the replacement
    // niri socket accepts the event stream again.
    Timer {
        id: _niriReconnect
        interval: 1500
        repeat: true
        running: root.isNiri && !_niriSocket.connected
        onTriggered: _niriSocket.connected = true
    }

    Socket {
        id: _niriSocket
        path: root.isNiri ? root._niriSock : ""
        connected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root._onNiriLine(line)
        }
        Component.onCompleted: if (root.isNiri) connected = true
        onConnectedChanged: {
            if (connected) {
                write("\"EventStream\"\n")
                flush()
            } else {
                _niriReconnect.restart()
            }
        }
    }
}
