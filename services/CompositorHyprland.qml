pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"

QtObject {
    id: root

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    property int _layoutTick: 0
    property var _liveTitles: ({})
    property string _activeTitle: ""
    property bool _refreshAgain: false
    property string _activeAddr: ""
    property bool _unfocused: false
    property string _special: ""
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    readonly property string _instanceSignature:
        String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")
    readonly property string _runtimeHyprDir:
        XdgPaths.runtimeDir.length > 0 ? XdgPaths.runtimeDir + "/hypr" : ""

    // A shell that survives a Hyprland restart goes blind: the event socket is bound to the
    // old instance and every dispatch keeps the stale signature. Watch the runtime directory
    // for a new instance and let the user unit bring the shell back onto the fresh one.
    property SupervisedProcess _restartWatch: SupervisedProcess {
        id: _restartWatch
        superviseWhen: SystemTools.hasInotifywait && SystemTools.hasSystemctl
            && root._instanceSignature.length > 0 && root._runtimeHyprDir.length > 0
        restartDelay: 10000
        // a missing runtime directory cannot be fixed by respawning; a later tool rescan retries
        giveUpCodes: [3]
        command: ["bash", "-c",
            "dir=\"$1\"; sig=\"$2\"; root=\"$3\"; " +
            "[ -d \"$dir\" ] || exit 3; " +
            "inotifywait -m -q -e create,moved_to --format '%f' \"$dir\" 2>/dev/null | " +
            "while IFS= read -r name; do " +
            "  [ \"$name\" = \"$sig\" ] && continue; " +
            // a surviving socket directory is only proof the compositor is here if the pid in
            // its lock is alive; a crash leaves the directory behind and the shell blind
            "  if [ -d \"$dir/$sig\" ]; then " +
            "    pid=\"\"; " +
            "    [ -r \"$dir/$sig/hyprland.lock\" ] && read -r pid < \"$dir/$sig/hyprland.lock\"; " +
            // an unreadable lock cannot prove the owner is gone, so leave the shell alone
            "    case \"$pid\" in \"\"|*[!0-9]*) continue ;; esac; " +
            "    kill -0 \"$pid\" 2>/dev/null && continue; " +
            "  fi; " +
            "  unit=silere-shell.service; " +
            "  systemctl --user is-active --quiet \"$unit\" || continue; " +
            // the user manager is shared: a throwaway checkout running this file must
            // not restart the shell the unit actually starts
            "  exec_start=\"$(systemctl --user show \"$unit\" -p ExecStart --value 2>/dev/null)\"; " +
            "  case \"$exec_start\" in " +
            "    *\" $root/shell.qml\"*|*\" $root/scripts/silere\"*\" run\"*) ;; " +
            "    *) continue ;; " +
            "  esac; " +
            "  systemctl --user restart \"$unit\"; " +
            "done",
            "bash", root._runtimeHyprDir, root._instanceSignature, Quickshell.shellDir]
    }

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

    // "emptynm" is hyprland's own selector: there is no workspace object to focus
    // until a window opens on it, so an id cannot stand in for this
    function focusNewWorkspace(output): void {
        if (output.length > 0) HyprDispatch.dispatchPair("focusmonitor", output, "workspace", "emptynm")
        else HyprDispatch.dispatch("workspace", "emptynm")
    }

    function moveActiveToWorkspace(wsId, output): void {
        HyprDispatch.dispatch("movetoworkspacesilent", wsId)
    }

    function moveActiveToNewWorkspace(output): void {
        const active = root.activeToplevel
        const ref = active && active.ref ? String(active.ref) : ""
        const addr = ref.length > 0
            ? (ref.startsWith("address:") ? ref : "address:" + ref) : ""
        const sourceOutput = active ? String(active.output || "") : ""
        if (output.length > 0 && output !== sourceOutput && addr.length > 0)
            HyprDispatch.moveWindowToWorkspaceOnMonitor(
                output, sourceOutput, "emptynm", addr)
        else
            HyprDispatch.dispatch("movetoworkspacesilent", "emptynm")
    }

    function focusToplevel(c): void {
        // a special workspace has a negative id and is reachable only by its name
        const special = String(c.wsName ?? "").startsWith("special:")
        const target = special ? c.wsName : c.wsRef
        const hasWs = special
            || (c.wsRef !== undefined && c.wsRef !== null && c.wsRef >= 0)
        const addr = c.ref
            ? (String(c.ref).startsWith("address:") ? String(c.ref) : "address:" + c.ref) : ""
        if (hasWs && addr.length > 0) HyprDispatch.dispatchPair("workspace", target, "focuswindow", addr)
        else if (hasWs) HyprDispatch.dispatch("workspace", target)
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
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        const next = Object.create(null)
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            // t.address/t.title land the instant hyprland reports them; lastIpcObject only
            // catches up on the next refreshToplevels() round-trip, well behind a new window
            if (!t || !t.address) continue
            const c = t.lastIpcObject
            next["0x" + t.address] = root._title(t.title || (c ? c.title : ""))
        }

        const oldKeys = Object.keys(root._liveTitles)
        const nextKeys = Object.keys(next)
        if (oldKeys.length === nextKeys.length
                && nextKeys.every(key => root._liveTitles[key] === next[key])) return
        root._liveTitles = next
    }

    // a background window can retitle many times a second; only the focused title is painted
    function _syncActiveTitle(): void {
        const t = Hyprland.activeToplevel
        if (!t || !t.address || root._unfocused) {
            if (root._activeTitle.length > 0) root._activeTitle = ""
            return
        }
        const c = t.lastIpcObject
        const next = root._title(t.title || (c ? c.title : ""))
        if (root._activeTitle !== next) root._activeTitle = next
    }

    function _titleEventAddress(data): string {
        const raw = String(data ?? "")
        const comma = raw.indexOf(",")
        const address = (comma >= 0 ? raw.slice(0, comma) : raw).trim()
        return address.startsWith("0x") ? address.slice(2) : address
    }

    function _queueTitleSync(data): void {
        if (!root._liveTitlesWanted || Idle.isIdle) return
        const eventAddress = root._titleEventAddress(data)
        const active = Hyprland.activeToplevel
        const activeAddress = active && active.address
            ? String(active.address) : root._activeAddr
        if (eventAddress.length > 0 && activeAddress.length > 0
                && eventAddress === activeAddress) {
            if (!_titleSync.running) _titleSync.start()
        } else if (!_backgroundTitleSync.running) {
            _backgroundTitleSync.start()
        }
    }

    property Timer _refreshSettleTimer: Timer {
        id: _refreshSettle
        interval: 80
        onTriggered: {
            root._layoutTick++
            root._syncLiveTitles()
            root._syncActiveTitle()
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
        onTriggered: root._syncActiveTitle()
    }

    // only jump-to-app heuristics read these, so a stale window costs nothing
    property Timer _backgroundTitleSyncTimer: Timer {
        id: _backgroundTitleSync
        interval: 1500
        onTriggered: root._syncLiveTitles()
    }

    property Connections _idleConn: Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) {
                _titleSync.stop()
                _backgroundTitleSync.stop()
            } else {
                root._syncLiveTitles()
                root._syncActiveTitle()
            }
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
                root._syncActiveTitle()
            } else {
                _titleSync.stop()
                _backgroundTitleSync.stop()
                // keep one last snapshot for focus heuristics, but stop subscribing it to title-only compositor events
                root._syncLiveTitles()
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
                cls: root._identity(c.class),
                initialClass: root._identity(c.initialClass),
                pid: c.pid ?? -1, ref: c.address,
                wsRef: wsId, wsId: wsId, output: wsOut[wsId] ?? "",
                wsName: c.workspace ? String(c.workspace.name ?? "") : "",
                focused: !root._unfocused && !!(Hyprland.activeToplevel && Hyprland.activeToplevel === t),
                focusRank: c.focusHistoryID ?? 9999,
                // hyprland's fullscreen is a mode enum, and 1 is merely maximized
                fullscreen: c.fullscreen === 2
            })
        }
        return out
    }

    readonly property var toplevels: {
        const base = root.workspaceToplevels
        const out = []
        for (let i = 0; i < base.length; i++) {
            const t = base[i]
            const liveTitle = root._liveTitles[t.ref]
            out.push({
                appId: t.appId,
                // titles are sampled imperatively. Reading the compositor title here would subscribe every consumer to title-only frames
                title: liveTitle !== undefined ? liveTitle : "",
                cls: t.cls, initialClass: t.initialClass,
                pid: t.pid, ref: t.ref,
                wsRef: t.wsRef, wsId: t.wsId, wsName: t.wsName, output: t.output,
                focused: t.focused,
                focusRank: t.focusRank,
                fullscreen: t.fullscreen
            })
        }
        return out
    }

    Component.onCompleted: Qt.callLater(function() {
        root._syncLiveTitles()
        root._syncActiveTitle()
    })

    // quickshell never clears activeToplevel: hyprland reports unfocus as an empty
    // activewindowv2 address and its parser bails out before the assignment
    readonly property var activeToplevel: {
        if (root._unfocused) return null
        const t = Hyprland.activeToplevel
        if (!t || !t.address) return null
        const addr = "0x" + t.address
        const tops = root.workspaceToplevels
        for (let i = 0; i < tops.length; i++)
            if (tops[i].ref === addr) return Object.assign({}, tops[i], {
                title: root._activeTitle
            })
        return null
    }

    function _updateSpecial(data): void {
        const parts = String(data ?? "").split(",")
        if (parts.length < 2) { root._special = ""; return }
        root._special = String(parts[parts.length - 2]).length > 0
            ? String(parts[parts.length - 1]) : ""
    }

    readonly property var _inertEvents: ({
        "openlayer": true, "closelayer": true, "submap": true, "activelayout": true,
        "screencast": true, "changefloatingmode": true, "bell": true, "pin": true,
        "minimized": true, "togglegroup": true, "moveintogroup": true,
        "moveoutofgroup": true, "ignoregrouplock": true, "lockgroups": true
    })

    property Connections _eventConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            // hyprland pairs each event with its v2 form; only v2 carries the title
            if (n === "windowtitle") return
            if (n === "windowtitlev2") {
                root._queueTitleSync(event.data)
                return
            }
            if (n === "activewindow") {
                // title-only half of activewindowv2; the v2 event below carries the address
                return
            }
            // none of these touch the workspace, monitor or toplevel lists: no floating, group, pin or minimize state is modelled (changefloatingmode alone fired 420 times in two hours)
            if (root._inertEvents[n] === true) return
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
                root._syncActiveTitle()
                root.refreshToplevels()
                root._layoutTick++
                return
            }
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
                || n === "fullscreen")
                root.refreshToplevels()
            // a window that never retitles after opening has no windowtitlev2 to arm this on
            if (n === "openwindow" && root._liveTitlesWanted && !Idle.isIdle && !_titleSync.running)
                _titleSync.start()
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
