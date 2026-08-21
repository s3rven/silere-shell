pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

QtObject {
    id: root

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    property int _layoutTick: 0
    property var _liveTitles: ({})
    property bool _refreshAgain: false
    property string _activeAddr: ""
    property bool _unfocused: false
    property string _special: ""
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    function _identity(value): string {
        return SafeText.singleLineText(value, Compositor.maxWindowIdentityChars)
    }

    function _title(value): string {
        return SafeText.singleLineText(value, Compositor.maxWindowTitleChars)
    }

    function monitorName(screen): string {
        const m = Hyprland.monitorFor(screen)
        return m ? m.name : ""
    }

    function focusWorkspace(wsId, output): void {
        if (output.length > 0) HyprDispatch.dispatchPair("focusmonitor", output, "workspace", wsId)
        else HyprDispatch.dispatch("workspace", wsId)
    }

    function moveActiveToWorkspace(wsId): void {
        HyprDispatch.dispatch("movetoworkspacesilent", wsId)
    }

    function focusToplevel(c): void {
        const hasWs = c.wsRef !== undefined && c.wsRef !== null && c.wsRef >= 0
        const addr = c.ref
            ? (String(c.ref).startsWith("address:") ? String(c.ref) : "address:" + c.ref) : ""
        if (hasWs && addr.length > 0) HyprDispatch.dispatchPair("workspace", c.wsRef, "focuswindow", addr)
        else if (hasWs) HyprDispatch.dispatch("workspace", c.wsRef)
        else if (addr.length > 0) HyprDispatch.dispatch("focuswindow", addr)
    }

    function refreshToplevels(): void {
        if (_refreshSettle.running) {
            root._refreshAgain = true
            return
        }
        Hyprland.refreshToplevels()
        _refreshSettle.restart()
    }

    function _syncLiveTitles(): void {
        if (!root._liveTitlesWanted) return
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const next = {}
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const c = t ? t.lastIpcObject : null
            if (!c || !c.address) continue
            next[c.address] = root._title(t.title || c.title)
        }

        const oldKeys = Object.keys(root._liveTitles)
        const nextKeys = Object.keys(next)
        if (oldKeys.length === nextKeys.length
                && nextKeys.every(key => root._liveTitles[key] === next[key])) return
        root._liveTitles = next
    }

    property Timer _refreshSettleTimer: Timer {
        id: _refreshSettle
        interval: 80
        onTriggered: {
            root._layoutTick++
            root._syncLiveTitles()
            if (!root._refreshAgain) return
            root._refreshAgain = false
            Hyprland.refreshToplevels()
            restart()
        }
    }

    // hyprland fires windowtitle and windowtitlev2 per title frame; coalesce the pair
    property Timer _titleSyncTimer: Timer {
        id: _titleSync
        interval: 180
        onTriggered: root._syncLiveTitles()
    }

    property Connections _idleConn: Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) _titleSync.stop()
            else root._syncLiveTitles()
        }
    }

    property Connections _settingsConn: Connections {
        target: ShellSettings
        function onWsShowAppIconsChanged(): void {
            if (ShellSettings.wsShowAppIcons) root.refreshToplevels()
        }
        function onShowWindowTitleChanged(): void {
            if (ShellSettings.showWindowTitle) {
                root.refreshToplevels()
                root._syncLiveTitles()
            } else {
                _titleSync.stop()
                root._liveTitles = ({})
            }
        }
    }

    readonly property string focusedMonitor: {
        root._layoutTick
        return Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name ?? "") : ""
    }

    readonly property int focusedWorkspaceRef: {
        root._layoutTick
        return Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id ?? -1) : -1
    }

    // hyprland has no compositor-side overview; OverviewState drives its own (overviewIsLive is false)
    readonly property bool overviewActive: false
    readonly property string specialOutput: root._special

    readonly property var workspaces: {
        root._layoutTick
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
    readonly property var workspaceToplevels: {
        root._layoutTick
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
                appId: root._identity((t.wayland && t.wayland.appId)
                    || c.class || c.initialClass),
                title: root._title(c.title),
                cls: root._identity(c.class),
                initialClass: root._identity(c.initialClass),
                pid: c.pid ?? -1, ref: c.address,
                wsRef: wsId, wsId: wsId, output: wsOut[wsId] ?? "",
                focused: !root._unfocused && !!(Hyprland.activeToplevel && Hyprland.activeToplevel === t),
                focusRank: c.focusHistoryID ?? 9999,
                fullscreen: !!c.fullscreen
            })
        }
        return out
    }

    readonly property var toplevels: {
        const base = root.workspaceToplevels
        if (!root._liveTitlesWanted) return base
        const out = []
        for (let i = 0; i < base.length; i++) {
            const t = base[i]
            const liveTitle = root._liveTitles[t.ref]
            out.push({
                appId: t.appId,
                // titles are sampled by _titleSync; reading t.title here would subscribe this binding to every title frame
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

    // quickshell never clears activeToplevel: hyprland reports unfocus as an empty
    // activewindowv2 address and its parser bails out before the assignment
    readonly property var activeToplevel: {
        if (root._unfocused) return null
        const t = Hyprland.activeToplevel
        if (!t) return null
        const tops = root.toplevels
        const c = t.lastIpcObject
        const addr = c ? c.address : null
        for (let i = 0; i < tops.length; i++)
            if (addr && tops[i].ref === addr) return tops[i]
        return null
    }

    function _updateSpecial(data): void {
        const parts = String(data ?? "").split(",")
        if (parts.length < 2) { root._special = ""; return }
        root._special = String(parts[parts.length - 2]).length > 0
            ? String(parts[parts.length - 1]) : ""
    }

    property Connections _eventConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "windowtitle" || n === "windowtitlev2" || n === "activewindow") {
                if (root._liveTitlesWanted && !Idle.isIdle && !_titleSync.running)
                    _titleSync.start()
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
                root._unfocused = addr.length === 0
                if (addr === root._activeAddr) {
                    if (root._liveTitlesWanted && !Idle.isIdle && !_titleSync.running)
                        _titleSync.start()
                    return
                }
                root._activeAddr = addr
                root.refreshToplevels()
                root._layoutTick++
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
                root.workspaceActivated(root.focusedMonitor)
            root._layoutTick++
        }
    }
}
