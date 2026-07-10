pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// backend-neutral compositor facade. picks niri (NIRI_SOCKET) or Hyprland and
// republishes both into one shape: workspaces, toplevels, activeToplevel, actions.
Singleton {
    id: root

    readonly property string _niriSock: String(Quickshell.env("NIRI_SOCKET") || "")
    readonly property bool isNiri:     _niriSock.length > 0
    readonly property bool isHyprland: !isNiri

    // only Hyprland has special/scratchpad workspaces; the gem hides its special visuals otherwise
    readonly property bool hasSpecialWorkspaces: isHyprland

    // { wsId, name, output, active, urgent, occupied, ref }. wsId is the number shown/activated
    // (Hyprland global id, niri per-output idx); ref is the backend handle used by actions.
    readonly property var workspaces:     isNiri ? _niriWorkspaces : _hyprWorkspaces
    // { appId, title, cls, initialClass, pid, ref, wsRef, wsId, output, focused, focusRank }.
    // focusRank: lower = more recently focused (Hyprland focusHistoryID; niri inverts its timestamp).
    readonly property var toplevels:      isNiri ? _niriToplevels : _hyprToplevels
    readonly property var activeToplevel: isNiri ? _niriActive : _hyprActive
    readonly property string focusedMonitor: isNiri ? _niriFocusedMon : _hyprFocusedMon
    // global handle of the focused workspace (Hyprland id / niri id); -1 = none
    readonly property int focusedWorkspaceRef: {
        if (root.isNiri) {
            const ws = root._niriWsRaw
            for (let i = 0; i < ws.length; i++)
                if (ws[i] && ws[i].is_focused) return ws[i].id
            return -1
        }
        root._hyprTick
        return Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id ?? -1) : -1
    }
    readonly property bool overviewActive:   isNiri ? _niriOverview : _hyprOverview
    readonly property bool activeFullscreen:  !!(activeToplevel && activeToplevel.fullscreen)
    // Hyprland output currently showing a special workspace, "" = none
    readonly property string specialOutput:  isNiri ? "" : _hyprSpecial
    readonly property bool ready: isNiri ? _niriReady : (workspaces.length > 0)

    // popups close when the active workspace on their monitor changes
    signal workspaceActivated(string output)
    // Hyprland scrolloverview plugin raw toggle; niri drives overviewActive directly
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

    // ---- actions ----

    function focusMonitor(name: string): void {
        if (!name || name.length === 0) return
        if (root.isNiri) { root._niriAction(["focus-monitor", name]); return }
        HyprActions._dispatch("focusmonitor", name)
    }

    function focusWorkspace(wsId, output): void {
        if (wsId === undefined || wsId === null || wsId < 0) return
        if (root.isNiri) {
            root._niriAction(["focus-workspace", String(wsId)])
            return
        }
        const mon = output || ""
        if (mon.length > 0) focusMonitor(mon)
        HyprActions._dispatch("workspace", wsId)
    }

    function moveActiveToWorkspace(wsId): void {
        if (wsId === undefined || wsId === null || wsId < 1) return
        if (root.isNiri) {
            root._niriAction(["move-window-to-workspace", "--focus", "false", String(wsId)])
            return
        }
        HyprActions._dispatch("movetoworkspacesilent", wsId)
    }

    // focus a specific toplevel (neutral object) and switch to its workspace
    function focusToplevel(c): void {
        if (!c) return
        if (root.isNiri) {
            if (c.ref) root._niriAction(["focus-window", "--id", String(c.ref)])
            return
        }
        if (c.wsRef !== undefined && c.wsRef !== null && c.wsRef >= 0)
            HyprActions._dispatch("workspace", c.wsRef)
        if (c.ref) {
            const addr = String(c.ref).startsWith("address:") ? String(c.ref) : "address:" + c.ref
            HyprActions._dispatch("focuswindow", addr)
        }
    }

    function refreshToplevels(): void {
        if (root.isHyprland) Hyprland.refreshToplevels()
    }

    // ===================== Hyprland backend =====================

    property int _hyprTick: 0

    function _hyprMonitorByName(name) {
        const mons = Hyprland.monitors ? (Hyprland.monitors.values ?? []) : []
        for (let i = 0; i < mons.length; i++)
            if (mons[i] && mons[i].name === name) return mons[i]
        return null
    }

    readonly property string _hyprFocusedMon: {
        root._hyprTick
        return Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name ?? "") : ""
    }

    readonly property var _hyprWorkspaces: {
        root._hyprTick
        if (root.isNiri) return []
        const mons = Hyprland.monitors ? (Hyprland.monitors.values ?? []) : []
        const activeByOutput = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            if (m && m.name && m.activeWorkspace) activeByOutput[m.name] = m.activeWorkspace.id
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
                urgent: ws.urgent ?? false, occupied: true, ref: ws.id
            })
        }
        return out
    }

    readonly property var _hyprToplevels: {
        root._hyprTick
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
                appId: (t.wayland && t.wayland.appId) || c.class || c.initialClass || "",
                title: c.title ?? (t.title ?? ""),
                cls: c.class ?? "", initialClass: c.initialClass ?? "",
                pid: c.pid ?? -1, ref: c.address,
                wsRef: wsId, wsId: wsId, output: wsOut[wsId] ?? "",
                focused: !!(Hyprland.activeToplevel && Hyprland.activeToplevel === t),
                focusRank: c.focusHistoryID ?? 9999,
                fullscreen: !!c.fullscreen
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
        // data is "[id,]wsname,monitor"; non-empty wsname before the monitor means a special is shown
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
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
                || n === "fullscreen" || n === "activewindow" || n === "activewindowv2")
                Hyprland.refreshToplevels()
            if (n === "activespecial" || n === "activespecialv2")
                root._updateSpecial(event.data)
            if (n === "scrolloverview")
                root.overviewRaw(event.data === "1")
            if (n === "workspace" || n === "workspacev2" || n === "focusedmon"
                || n === "focusedmonv2" || n === "activemon")
                root.workspaceActivated(root._hyprFocusedMon)
            root._hyprTick++
        }
    }

    // ===================== niri backend =====================

    property var _niriWsRaw: []
    property var _niriWinRaw: []
    property bool _niriOverview: false
    property bool _niriReady: false

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

    // niri window.workspace_id is a global id; join to the workspace list for display idx + output
    readonly property var _niriToplevels: {
        const wins = root._niriWinRaw
        const ws = root._niriWsRaw
        const byId = {}
        for (let i = 0; i < ws.length; i++) if (ws[i]) byId[ws[i].id] = ws[i]
        const out = []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            if (!w) continue
            const home = byId[w.workspace_id] || null
            const app = w.app_id ?? ""
            out.push({
                appId: app, title: w.title ?? "",
                cls: app, initialClass: app,
                pid: w.pid ?? -1, ref: w.id,
                wsRef: w.workspace_id, wsId: home ? home.idx : -1,
                output: home ? (home.output ?? "") : "",
                focused: !!w.is_focused,
                focusRank: w.focus_timestamp ? -Number(w.focus_timestamp.secs ?? 0) : 9999,
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

    function _onNiriLine(line): void {
        const text = String(line || "").trim()
        if (text.length === 0 || text.charAt(0) !== "{") return
        let ev
        try { ev = JSON.parse(text) } catch (e) { return }

        if (ev.WorkspacesChanged) {
            root._niriWsRaw = ev.WorkspacesChanged.workspaces || []
            root._niriReady = true
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
            root._niriWinRaw = ev.WindowsChanged.windows || []
            return
        }
        if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window
            if (!w) return
            const wins = root._niriWinRaw.slice()
            let found = false
            for (let i = 0; i < wins.length; i++) {
                if (wins[i] && wins[i].id === w.id) { wins[i] = w; found = true }
                else if (wins[i] && w.is_focused) wins[i] = Object.assign({}, wins[i], { is_focused: false })
            }
            if (!found) wins.push(w)
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
        if (ev.OverviewOpenedOrClosed) {
            root._niriOverview = !!ev.OverviewOpenedOrClosed.is_open
            return
        }
    }

    Socket {
        id: _niriSocket
        path: root.isNiri ? root._niriSock : ""
        connected: root.isNiri
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root._onNiriLine(line)
        }
        onConnectedChanged: {
            if (connected) write("\"EventStream\"\n")
            else root._niriReady = false
        }
    }
}
