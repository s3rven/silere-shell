pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../config"

QtObject {
    id: root
    property string keyboardLayout: ""
    // 0 = not read yet; Hyprland lists the main keyboard's layouts comma-separated ("us,de")
    property int keyboardLayoutCount: 0
    function cycleKeyboardLayout(): void {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
    }
    property string submap: ""
    // the event names the submap entered, empty on the way back; "default" is what hyprctl calls that normal one
    function submapFrom(data): string {
        const name = SafeText.singleLineText(data, 64)
        return name === "default" ? "" : name
    }
    function leaveSubmap(): void {
        if (root.submap.length > 0) HyprDispatch.dispatch("submap", "reset")
    }
    // a shell started inside a mode (a restart while resizing) hears no event until the mode changes, so it asks once
    property int _submapRevision: 0
    function _acceptSubmapSnapshot(raw: string, revision: int): void {
        if (revision !== root._submapRevision) return
        try {
            const name = JSON.parse(raw)
            if (typeof name === "string") root.submap = root.submapFrom(name)
        } catch (e) {}
    }
    property BoundedProcess _submapProbe: BoundedProcess {
        id: _submapProbe
        property int revision: -1
        timeoutMs: 3000
        command: ["hyprctl", "-j", "submap"]
        stdout: StdioCollector { id: _submapOut }
        onExited: code => {
            if (_submapProbe.completedSuccessfully(code)) root._acceptSubmapSnapshot(_submapOut.text, _submapProbe.revision)
        }
    }
    property bool _keyboardWanted: ShellSettings.barShowKeyboard
    property int _keyboardRevision: 0
    property int _keyboardProbeRevision: 0
    property bool _keyboardRefreshAgain: false
    on_KeyboardWantedChanged: root._refreshKeyboard()
    function _refreshKeyboard(): void {
        if (!root._keyboardWanted) return
        if (_keyboardProbe.running) {
            root._keyboardRefreshAgain = true
            return
        }
        root._keyboardProbeRevision = root._keyboardRevision
        _keyboardProbe.running = true
    }
    function _acceptKeyboardSnapshot(raw: string, revision: int): void {
        try {
            const keyboards = JSON.parse(raw).keyboards
            if (!Array.isArray(keyboards)) return
            const physical = keyboards.filter(k => k && !root._isVirtualKeyboard(k.name))
            const pool = physical.length > 0 ? physical : keyboards.filter(k => !!k)
            const main = pool.find(k => k.main) || pool[0]
            // a layout switch leaves the configured count useful, but its newer socket event owns the name
            if (revision === root._keyboardRevision)
                root.keyboardLayout = main ? SafeText.singleLineText(main.active_keymap || "", 128) : ""
            root.keyboardLayoutCount = main ? String(main.layout ?? "").split(",").filter(l => l.trim().length > 0).length : 0
        } catch (e) {}
    }
    // wtype, emoji pickers and remote input upload their own keymap, often nameless ("error"), and become main while typing;
    // Hyprland names most "hl-virtual-keyboard*", but a client may name its own ("launcher-snippet-virtual-keyboard")
    function _isVirtualKeyboard(name): bool {
        return String(name ?? "").includes("virtual-keyboard")
    }
    function _updateKeyboardLayout(data): void {
        const value = String(data ?? "")
        const comma = value.indexOf(",")
        if (comma <= 0 || root._isVirtualKeyboard(value.slice(0, comma))) return
        const layout = SafeText.singleLineText(value.slice(comma + 1), 128)
        if (layout.length === 0) return
        root._keyboardRevision++
        root.keyboardLayout = layout
    }
    property BoundedProcess _keyboardProbe: BoundedProcess {
        id: _keyboardProbe
        timeoutMs: 3000
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector { id: _keyboardOut }
        onExited: code => {
            if (_keyboardProbe.completedSuccessfully(code))
                root._acceptKeyboardSnapshot(_keyboardOut.text, root._keyboardProbeRevision)
            // config reloads can arrive while devices is in flight; read again after running falls
            if (root._keyboardRefreshAgain) {
                root._keyboardRefreshAgain = false
                Qt.callLater(root._refreshKeyboard)
            }
        }
    }

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)
    signal screencast(bool started)
    // a saved config, so what reads it (the Keybinds page) can read it again
    signal configReloaded()

    property int _layoutTick: 0
    property var _liveTitles: ({})
    property string _activeTitle: ""
    property bool _refreshAgain: false
    property string _activeAddr: ""
    property bool _unfocused: false
    // focus order seen this session, by bare address, filled in place: a client list per focus change only refreshed focusHistoryID
    readonly property var _focusOrder: ({})
    property int _focusSeq: 0
    // negative, like niri's: a window focused this session outranks every one not. The focused one ranks first by its
    // flag: quickshell rebuilds the models on its own focus change, before the event reaches _focusOrder
    function focusRankOf(address, ipc, focused): real {
        if (focused) return -Infinity
        const seq = root._focusOrder[address]
        return seq !== undefined ? -seq : (ipc && ipc.focusHistoryID !== undefined ? ipc.focusHistoryID : 9999)
    }
    // per output: two monitors can each show a special workspace
    property var _specialOn: ({})
    readonly property bool _liveTitlesWanted: ShellSettings.showWindowTitle

    readonly property string _instanceSignature:
        String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")
    readonly property string _runtimeHyprDir:
        XdgPaths.runtimeDir.length > 0 ? XdgPaths.runtimeDir + "/hypr" : ""

    // a shell that survives a Hyprland restart goes blind: the event socket is bound to the
    // old instance and every dispatch keeps the stale signature. Watch the runtime directory
    // for a new instance and let the user unit bring the shell back onto the fresh one
    property SupervisedProcess _restartWatch: SupervisedProcess {
        id: _restartWatch
        superviseWhen: root._unitRunsHere && SystemTools.hasInotifywait
            && root._instanceSignature.length > 0 && root._runtimeHyprDir.length > 0
        restartDelay: 10000
        // a missing runtime directory cannot be fixed by respawning; a later tool rescan retries
        giveUpCodes: [3]
        command: ["bash", "-c",
            "dir=\"$1\"; sig=\"$2\"; root=\"$3\"; " +
            "[ -d \"$dir\" ] || exit 3; " +
            // a signal to qs skips its cleanup, so the kernel ends the watcher with it
            "setpriv --pdeathsig KILL true >/dev/null 2>&1 && set -- setpriv --pdeathsig KILL || set --; " +
            // quickshell kills only its direct child: a piped loop outlived every reload, so the reader ends on eof
            "exec \"$@\" inotifywait -m -q -e create,moved_to --format '%f' \"$dir\" 2>/dev/null > >(" +
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
            // the user manager is shared: a throwaway checkout running this file must not restart the shell the unit actually starts
            "  . \"$root/scripts/lib/unit.sh\" 2>/dev/null && _silere_unit_runs_checkout \"$root\" || continue; " +
            "  systemctl --user restart \"$unit\"; " +
            "done)",
            "bash", root._runtimeHyprDir, root._instanceSignature, Quickshell.shellDir]
    }

    function retryWatcher(): void {
        if (_restartWatch.gaveUp) _restartWatch.retry()
    }

    // quickshell never reconnects a dropped event socket while hyprland keeps running, so the watcher above never fires; wayland focus flips with no socket event between them prove it dead
    property int _eventSeq: 0
    property int _seqAtFlip: -1
    property int _silentFlips: 0
    property bool _socketDead: false
    property Connections _socketWatch: Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (ToplevelManager.activeToplevel) root._noteFocusFlip()
        }
    }
    function _noteFocusFlip(): void {
        if (root._socketDead) return
        root._silentFlips = root._eventSeq === root._seqAtFlip ? root._silentFlips + 1 : 0
        root._seqAtFlip = root._eventSeq
        if (root._silentFlips >= 3 && !root._socketConfirm.running) {
            root._seqAtConfirm = root._eventSeq
            root._socketConfirm.restart()
        }
    }
    // wayland and the event socket are read separately, so the flips' own events can still be queued behind them.
    // Dead only if nothing at all arrived meanwhile: a flip right before the deadline can have its own event unread
    property int _seqAtConfirm: -1
    property Timer _socketConfirm: Timer {
        interval: 4000
        onTriggered: if (!root._socketDead && root._eventSeq === root._seqAtConfirm) root._eventSocketDead()
    }
    property BoundedProcess _socketRestart: BoundedProcess {
        timeoutMs: 5000
        command: ["systemctl", "--user", "--no-block", "try-restart", "silere-shell.service"]
    }
    function _eventSocketDead(): void {
        root._socketDead = true
        const restart = root._unitRunsHere
        console.warn("silere-shell: the hyprland event socket went silent"
            + (restart ? "; restarting the shell" : "; restart the shell to recover"))
        if (restart) _socketRestart.running = true
    }

    property Binding _luaDispatch: Binding {
        target: HyprDispatch
        property: "useLua"
        value: Hyprland.usingLua
    }

    // the watcher can only ever restart the unit, so without one it would idle all session
    property bool _unitRunsHere: false
    property BoundedProcess _unitProbe: BoundedProcess {
        timeoutMs: 5000
        command: ["bash", "-c", ". \"$1/scripts/lib/unit.sh\" && _silere_unit_runs_checkout \"$1\"",
            "bash", Quickshell.shellDir]
        onExited: code => root._unitRunsHere = root._unitProbe.completedSuccessfully(code)
    }
    function _probeUnit(): void {
        // a test copy of this checkout matches the unit too
        if (!SystemTools.ready || !SystemTools.hasSystemctl || _unitProbe.running
                || Quickshell.env("SILERE_SANDBOX") === "1") return
        _unitProbe.running = true
    }
    property Connections _unitProbeRearm: Connections {
        target: SystemTools
        function onReadyChanged() { root._probeUnit() }
        function onScanRevisionChanged() { root._probeUnit() }
    }

    // a blur request does nothing before 0.56, which lacks the protocol, or with decoration:blur:enabled off.
    // read at startup, on a config reload and as a popup opens (hl.config turns blur off with no event): popups turn
    // solid while nothing frosts them
    property string blurBlocker: ""
    property bool _blurAgain: false
    property BoundedProcess _blurProbe: BoundedProcess {
        timeoutMs: 3000
        command: ["sh", "-c", "hyprctl -j version && hyprctl -j getoption decoration:blur:enabled"]
        stdout: StdioCollector { id: _blurOut }
        onExited: code => {
            root.blurBlocker = root._blurProbe.completedSuccessfully(code) ? root.blurBlockerFrom(_blurOut.text) : ""
            // a reload during the read may have changed blur after it
            if (root._blurAgain) {
                root._blurAgain = false
                Qt.callLater(root.checkBlur)
            }
        }
    }
    function blurBlockerFrom(out: string): string {
        const v = /"(?:version|tag)":\s*"v?(\d+)\.(\d+)/.exec(out)
        if (v && Number(v[1]) === 0 && Number(v[2]) < 56) return "Needs Hyprland 0.56"
        return /"bool":\s*false/.test(out) ? "Off in Hyprland" : ""
    }
    // hyprctl ships with Hyprland, and a missing one only fails the probe, which blames nothing
    function checkBlur(): void {
        if (_blurProbe.running) root._blurAgain = true
        else _blurProbe.running = true
    }

    property Connections _restartWatchRetry: Connections {
        target: SystemTools
        function onScanRevisionChanged() {
            if (SystemTools.hasInotifywait && SystemTools.hasSystemctl) root.retryWatcher()
        }
    }

    // a window's identities never change, and every model rebuild cleaned three per window; external strings, so no prototype
    readonly property var _identities: Object.create(null)
    function _identity(value): string {
        const raw = String(value ?? "")
        const known = root._identities[raw]
        if (known !== undefined) return known
        if (Object.keys(root._identities).length >= 256)
            for (const key of Object.keys(root._identities)) delete root._identities[key]
        return (root._identities[raw] = SafeText.singleLineText(raw, Compositor.maxWindowIdentityChars))
    }

    function _title(value): string {
        return Compositor.windowTitle(value)
    }

    function monitorName(screen): string {
        const m = Hyprland.monitorFor(screen)
        return m ? m.name : ""
    }
    function monitorScale(screen): real {
        const m = Hyprland.monitorFor(screen)
        return m && isFinite(m.scale) && m.scale > 0 ? m.scale : 0
    }

    function focusWorkspace(wsId, output): void {
        if (output.length > 0) HyprDispatch.dispatchPair("focusmonitor", output, "workspace", wsId)
        else HyprDispatch.dispatch("workspace", wsId)
    }

    function moveActiveToWorkspace(wsId, output): void {
        HyprDispatch.dispatch("movetoworkspacesilent", wsId)
    }

    function focusToplevel(c): void {
        // a special workspace has a negative id and is reachable only by its name
        const special = String(c.wsName ?? "").startsWith("special:")
        const target = special ? c.wsName : c.wsRef
        const hasWs = special
            || (c.wsRef !== undefined && c.wsRef !== null && c.wsRef >= 0)
        const addr = c.ref
            ? (String(c.ref).startsWith("address:") ? String(c.ref) : "address:" + c.ref) : ""
        // the workspace already shown: binds:workspace_back_and_forth takes a switch to it as "go back", and
        // focuswindow then came straight back, two switches for none
        const here = !special && c.wsRef === root.focusedWorkspaceRef
        if (hasWs && !here && addr.length > 0) HyprDispatch.dispatchPair("workspace", target, "focuswindow", addr)
        else if (addr.length > 0) HyprDispatch.dispatch("focuswindow", addr)
        else if (hasWs && !here) HyprDispatch.dispatch("workspace", target)
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
        const tops = root._liveToplevels()
        const next = Object.create(null)
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            // t.address/t.title land the instant hyprland reports them; lastIpcObject only
            // catches up on the next refreshToplevels() round-trip, well behind a new window
            if (!t || !t.address) continue
            next["0x" + t.address] = root._title(t.title || (t.lastIpcObject ? t.lastIpcObject.title : ""))
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
        const next = root._title(t.title || (t.lastIpcObject ? t.lastIpcObject.title : ""))
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
            const wsVals = Hyprland.workspaces ? (Hyprland.workspaces.values ?? []) : []
            const missing = root._missingWorkspaceId(wsVals, root._liveToplevels())
            const monitorless = missing > 0 ? -1 : root.monitorlessWorkspaceId(wsVals)
            if (missing > 0) root._requestWorkspaceRefresh("missing:" + missing)
            else if (monitorless > 0) root._requestWorkspaceRefresh("monitor:" + monitorless)
            else root._workspaceRefreshKey = ""
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
        void root._layoutTick
        return Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name ?? "") : ""
    }

    readonly property int focusedWorkspaceRef: {
        void root._layoutTick
        return Hyprland.focusedWorkspace ? root._workspaceId(Hyprland.focusedWorkspace) : -1
    }

    // hyprland has no compositor-side overview; OverviewState drives its own (overviewIsLive is false)
    readonly property bool overviewActive: false
    // 0.56 hands a click outside a popup to its exclusive card window; from 0.57 it goes to whatever is under it, and this grab closes the popup instead, on any monitor. Without it popups keep their full-screen dismiss windows
    readonly property Component popupGrab: {
        const grab = Qt.createComponent("CompositorHyprlandGrab.qml")
        if (grab.status === Component.Ready) return grab
        console.warn("silere-shell: Quickshell has no Hyprland focus grab; popups fall back to a full-screen dismiss window:", grab.errorString())
        return null
    }
    readonly property var specialOutputs: Object.keys(root._specialOn)

    // quickshell#1268: a j/clients reply still in flight when a window closes brings it back for good, so an address hyprland closed stays out until it opens one again
    property var _closedAddrs: ({})
    function _setClosed(data, closed: bool): void {
        const addr = root._titleEventAddress(data)
        if (addr.length === 0) return
        const key = "0x" + addr
        if ((root._closedAddrs[key] === true) === closed) return
        const next = Object.assign({}, root._closedAddrs)
        if (closed) {
            delete root._focusOrder[addr]
            next[key] = true
            const keys = Object.keys(next)
            if (keys.length > 64)
                delete next[root._evictable(keys, root._liveToplevels({}))]
        } else {
            delete next[key]
        }
        root._closedAddrs = next
    }
    // a closed address quickshell no longer lists needs no filtering; dropping a listed ghost brings it back for good
    function _evictable(keys, tops): string {
        const listed = {}
        for (const t of tops) if (t && t.address) listed["0x" + t.address] = true
        return keys.find(k => listed[k] !== true) ?? keys[0]
    }
    function _withoutClosed(tops, closed, addressOf = t => t.address): var {
        return tops.filter(t => {
            const a = t ? addressOf(t) : ""
            return !(a && closed["0x" + a] === true)
        })
    }
    // quickshell signals every window's address again with each client reply, so a binding that read t.address reran once per window
    readonly property var _addressOf: new Map()
    function _addr(t): string { return (t && root._addressOf.get(t)) || "" }
    // the map fills on a later tick than quickshell's own update: a window that opens focused or urgent is missing from
    // it when activeToplevel and urgentRefs first look, so those two read this. Bumped only when the windows change
    property int _addressRev: 0
    // an empty closed set lists every window quickshell holds, ghosts included: only the eviction and the copies ask for that
    function _liveToplevels(closed = root._closedAddrs): var {
        return root._withoutClosed(Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : [], closed, t => root._addr(t))
    }
    // its own list: urgency read inside the window model would rebuild that model for every consumer on each flip
    readonly property var urgentRefs: {
        void root._addressRev
        return root._liveToplevels().filter(t => t && t.urgent && root._addr(t)).map(t => "0x" + root._addr(t))
    }

    // quickshell prunes a workspace created while its startup snapshot is in flight; a window still names the workspace
    property string _workspaceRefreshKey: ""
    property int _workspaceRefreshTries: 0
    // a plain copy: a lastIpcObject kept in a variable makes Qt watch the toplevel, and Qt can free that watch mid-update (quickshell#1535)
    function _ipcOf(t): var { return t && t.lastIpcObject ? JSON.parse(JSON.stringify(t.lastIpcObject)) : null }
    // copied once per reply: inside the models, every reply re-ran them once per window and a switch made window-count-squared copies
    property var _ipcCopies: ({})
    function ipcCopiesOf(tops): var {
        const out = Object.create(null)
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (t && t.address) out[t.address] = root._ipcOf(t)
        }
        return out
    }
    // the one place a window's address is read for the models, outside any binding; the copies' change reruns them
    function _syncIpcCopies(): void {
        const tops = root._liveToplevels({})
        const known = root._addressOf
        const next = new Map()
        for (const t of tops) if (t && t.address) next.set(t, t.address)
        let changed = next.size !== known.size
        for (const [t, address] of next) if (known.get(t) !== address) changed = true
        known.clear()
        for (const [t, address] of next) known.set(t, address)
        root._ipcCopies = root.ipcCopiesOf(tops)
        // after the copies, so the window models have rebuilt once by the time these bindings look again
        if (changed) root._addressRev++
    }
    // quickshell's own model, not a list: a list built from it is new on every open and close, and rebuilt every watcher
    property Instantiator _ipcWatch: Instantiator {
        model: Hyprland.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { Qt.callLater(root._syncIpcCopies) }
        }
        onObjectAdded: Qt.callLater(root._syncIpcCopies)
        onObjectRemoved: Qt.callLater(root._syncIpcCopies)
    }

    function _missingWorkspaceId(workspaces, toplevels): int {
        const known = {}
        for (let i = 0; i < workspaces.length; i++)
            if (workspaces[i]) known[workspaces[i].id] = true
        for (let i = 0; i < toplevels.length; i++) {
            const c = root._ipcOf(toplevels[i])
            const id = root._wsNumber(c ? c.workspace : null)
            if (id > 0 && !known[id]) return id
        }
        return -1
    }
    // a workspace quickshell made from its create event has no monitor until a workspace list arrives, so it is never active
    function monitorlessWorkspaceId(workspaces): int {
        for (let i = 0; i < workspaces.length; i++) {
            const ws = workspaces[i]
            if (ws && ws.id > 0 && !ws.monitor) return ws.id
        }
        return -1
    }
    // a request made while quickshell's own is in flight is dropped, so a gap that outlives one gets a few more
    function _requestWorkspaceRefresh(key: string): void {
        if (key !== root._workspaceRefreshKey) {
            root._workspaceRefreshKey = key
            root._workspaceRefreshTries = 0
        }
        if (root._workspaceRefreshTries >= 3) return
        root._workspaceRefreshTries++
        Hyprland.refreshWorkspaces()
    }

    // quickshell 0.3.2 resolves focusedmon's workspace by name, and since Hyprland 0.57 the event names it by its id, so a
    // workspace named otherwise is dropped (quickshell#1427). Every pointer crossing to another monitor sends one: only that
    // case pays for a monitors request, which also opens a request socket (quickshell#1538 crashes in one)
    function focusedMonLosesWorkspace(data, workspaces): bool {
        const text = String(data ?? "")
        const comma = text.indexOf(",")
        if (comma < 0) return true
        const name = text.slice(comma + 1)
        return !Array.from(workspaces || []).some(w => w && String(w.name ?? "") === name)
    }

    // hyprland 0.57 replaces a window's workspace id with a string address; like quickshell, only a numbered one keeps its id
    function _wsNumber(ws): int {
        if (!ws) return -1
        if (typeof ws.id === "number") return ws.id
        const addr = String(ws.address ?? "")
        return /^-?[0-9]+$/.test(addr) ? Number(addr) : -1
    }

    // hyprland 0.57 gives a named or special workspace no id and quickshell reads that as -1, which
    // the bar takes for "no data yet". Named ids ran below -1337 before that, so they stay there
    readonly property int namedWorkspaceId: -1338
    function _workspaceId(ws): int {
        if (!ws) return -1
        return ws.id === -1 && String(ws.name ?? "").length > 0 ? root.namedWorkspaceId : ws.id
    }

    readonly property var workspaces: {
        void root._layoutTick
        const mons = Hyprland.monitors ? (Hyprland.monitors.values ?? []) : []
        // the workspace itself, not its id: every named workspace shares one
        const activeByOutput = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            if (m && m.name && m.activeWorkspace) activeByOutput[m.name] = m.activeWorkspace
        }
        // hyprland keeps a workspace object alive after its last window closes, so existence is
        // not occupancy; count real toplevels or an emptied workspace stays lit like a full one
        const tops = root._liveToplevels()
        const copies = root._ipcCopies
        const winCount = {}
        for (let i = 0; i < tops.length; i++) {
            const c = tops[i] ? copies[root._addr(tops[i])] : null
            if (!c || !c.address) continue
            const id = root._wsNumber(c.workspace)
            if (id > 0) winCount[id] = (winCount[id] ?? 0) + 1
        }
        const vals = Hyprland.workspaces ? (Hyprland.workspaces.values ?? []) : []
        const out = []
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (!ws) continue
            const output = ws.monitor ? (ws.monitor.name ?? "") : ""
            const id = root._workspaceId(ws)
            out.push({
                wsId: id, name: ws.name ?? "", output: output,
                active: activeByOutput[output] === ws,
                urgent: ws.urgent ?? false,
                occupied: (winCount[id] ?? 0) > 0, ref: id
            })
        }
        return out
    }

    // shared layout base built once; the title-facing list below only overlays the sampled strings
    readonly property var workspaceToplevels: {
        void root._layoutTick
        // by name too: named and special workspaces share an id, and each can sit on its own monitor
        const wsOutById = Object.create(null)
        const wsOutByName = Object.create(null)
        const wsVals = Hyprland.workspaces ? (Hyprland.workspaces.values ?? []) : []
        for (let i = 0; i < wsVals.length; i++) {
            const ws = wsVals[i]
            if (!ws) continue
            const output = ws.monitor ? (ws.monitor.name ?? "") : ""
            // a display name can be another workspace's number, so it must never replace that id's output
            wsOutById[ws.id] = output
            wsOutByName[ws.name ?? ""] = output
        }
        const tops = root._liveToplevels()
        const copies = root._ipcCopies
        const out = []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const address = root._addr(t)
            const c = address ? copies[address] : null
            if (!c || !c.address) continue
            const focused = !root._unfocused && !!(Hyprland.activeToplevel && Hyprland.activeToplevel === t)
            const wsName = c.workspace ? String(c.workspace.name ?? "") : ""
            // -1 is reserved for a window with no workspace, which window matching skips
            const wsId = root._workspaceId({ id: root._wsNumber(c.workspace), name: wsName })
            out.push({
                appId: root._identity((t.wayland && t.wayland.appId)
                    || c.class || c.initialClass),
                cls: root._identity(c.class),
                initialClass: root._identity(c.initialClass),
                pid: c.pid ?? -1, ref: c.address,
                wsRef: wsId, wsId: wsId, output: (wsId > 0 ? wsOutById[wsId] : wsOutByName[wsName]) ?? "",
                wsName: wsName,
                focused: focused,
                focusRank: root.focusRankOf(address, c, focused),
                // hyprland's fullscreen is a mode bitmask: 1 maximized, 2 fullscreen, 3 both
                fullscreen: (Number(c.fullscreen) & 2) !== 0
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

    Component.onCompleted: {
        root._refreshKeyboard()
        _submapProbe.revision = root._submapRevision
        _submapProbe.running = true
        root._probeUnit()
        root.checkBlur()
        Qt.callLater(function() {
            root._syncLiveTitles()
            root._syncActiveTitle()
            root._seedSpecial()
        })
    }

    // quickshell never clears activeToplevel: hyprland reports unfocus as an empty activewindowv2 address and its parser bails out before the assignment
    readonly property var activeToplevel: {
        if (root._unfocused) return null
        const t = Hyprland.activeToplevel
        void root._addressRev
        const bare = root._addr(t)
        if (!bare) return null
        const addr = "0x" + bare
        const tops = root.workspaceToplevels
        for (let i = 0; i < tops.length; i++)
            if (tops[i].ref === addr) return Object.assign({}, tops[i], {
                title: root._activeTitle
            })
        return null
    }

    function _updateSpecial(data): void {
        const parts = String(data ?? "").split(",")
        const output = parts.length >= 2 ? String(parts[parts.length - 1]) : ""
        if (output.length === 0) return
        root._specialHeard[output] = true
        const next = Object.assign({}, root._specialOn)
        if (String(parts[parts.length - 2]).length > 0) next[output] = true
        else delete next[output]
        root._specialOn = next
    }

    function _forgetSpecial(output: string): void {
        if (output.length === 0) return
        // a monitor snapshot already in flight can still name the disconnected output
        root._specialHeard[output] = true
        if (root._specialOn[output] !== true) return
        const next = Object.assign({}, root._specialOn)
        delete next[output]
        root._specialOn = next
    }

    // a special workspace already shown when the shell starts sent its activespecial before anyone listened.
    // The first monitor read names it; later reads can trail the events and are not refreshed by them, so
    // only that first read counts, and only for an output no event has spoken for since
    readonly property var _specialHeard: ({})
    property bool _specialSeeded: false
    function specialFromMonitors(mons, heard): var {
        const on = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            const name = m && m.lastIpcObject && m.lastIpcObject.specialWorkspace
                ? m.lastIpcObject.specialWorkspace.name : ""
            if (m && m.name && !heard[m.name] && typeof name === "string" && name.length > 0) on[m.name] = true
        }
        return on
    }
    function _seedSpecial(): void {
        if (root._specialSeeded) return
        const mons = Hyprland.monitors ? (Hyprland.monitors.values ?? []) : []
        if (!mons.some(m => m && m.lastIpcObject && m.lastIpcObject.name)) return
        root._specialSeeded = true
        const seeded = root.specialFromMonitors(mons, root._specialHeard)
        if (Object.keys(seeded).length > 0) root._specialOn = Object.assign({}, root._specialOn, seeded)
    }
    property Connections _monitorsConn: Connections {
        target: Hyprland.monitors
        function onValuesChanged() { root._seedSpecial() }
    }

    // quickshell leaves ShellScreen.serialNumber empty on wayland (quickshell#903); hyprland's monitor reply has the EDID serial
    property var monitorSerials: ({})
    function serialsFrom(mons): var {
        const out = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            const name = m && m.lastIpcObject ? m.lastIpcObject.name : undefined
            const serial = m && m.lastIpcObject ? m.lastIpcObject.serial : undefined
            if (typeof name === "string" && typeof serial === "string" && serial.trim().length > 0)
                out[name] = serial.trim()
        }
        return out
    }
    function _syncSerials(): void {
        const next = root.serialsFrom(Hyprland.monitors ? (Hyprland.monitors.values ?? []) : [])
        if (JSON.stringify(next) !== JSON.stringify(root.monitorSerials)) root.monitorSerials = next
    }
    // the reply lands after the monitor is listed, and only its own signal says so
    property Instantiator _serialWatch: Instantiator {
        model: Hyprland.monitors
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { Qt.callLater(root._syncSerials) }
        }
        onObjectAdded: Qt.callLater(root._syncSerials)
        onObjectRemoved: Qt.callLater(root._syncSerials)
    }

    readonly property var _inertEvents: ({
        "openlayer": true, "closelayer": true, "activelayout": true,
        "screencastv2": true, "changefloatingmode": true, "bell": true, "pin": true,
        "minimized": true, "togglegroup": true, "moveintogroup": true,
        "moveoutofgroup": true, "ignoregrouplock": true, "lockgroups": true
    })

    property Connections _eventConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            root._eventSeq++
            const n = event.name
            if (n === "activelayout") {
                root._updateKeyboardLayout(event.data)
                return
            }
            if (n === "submap") {
                root._submapRevision++
                root.submap = root.submapFrom(event.data)
                return
            }
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
            // fires per captured frame: kept off the layout tick
            if (n === "screencast") {
                root.screencast(String(event.data ?? "").startsWith("1,"))
                return
            }
            // none of these touch the workspace, monitor or toplevel lists: no floating, group, pin or minimize state is modelled (changefloatingmode alone fired 420 times in two hours)
            if (root._inertEvents[n] === true) return
            // twins of workspacev2, createworkspacev2, destroyworkspacev2 and movewindowv2 (hyprland 0.33+): handling both rebuilt the models twice per switch
            if (n === "workspace" || n === "createworkspace" || n === "destroyworkspace" || n === "movewindow") return
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
                if (addr.length > 0) root._focusOrder[addr] = ++root._focusSeq
                // no layout tick: quickshell's activeToplevel and _unfocused already rebuilt the models, and a focus that
                // moves monitor or workspace brings its own focusedmon or workspacev2
                root._syncActiveTitle()
                return
            }
            if (n === "openwindow" || n === "closewindow") root._setClosed(event.data, n === "closewindow")
            if (n === "openwindow" || n === "closewindow" || n === "movewindowv2"
                || n === "fullscreen" || n === "changeworkspaceid")
                root.refreshToplevels()
            // a new workspace changes no window: only the settle's look for a workspace still without its monitor is wanted
            else if (n === "createworkspacev2" && !_refreshSettle.running) _refreshSettle.restart()
            // a window that never retitles after opening has no windowtitlev2 to arm this on
            if (n === "openwindow" && root._liveTitlesWanted && !Idle.isIdle && !_titleSync.running)
                _titleSync.start()
            if (n === "activespecial" || n === "activespecialv2")
                root._updateSpecial(event.data)
            else if (n === "monitorremoved" || n === "monitorremovedv2")
                root._forgetSpecial(n === "monitorremoved" ? String(event.data ?? "")
                    : String(event.data ?? "").split(",")[1] || "")
            // a monitor an event named before its first read had no IPC object when the list changed
            else root._seedSpecial()
            if (n === "scrolloverview")
                root.overviewRaw(event.data === "1")
            if (n === "changeworkspaceid")
                root._requestWorkspaceRefresh("id:" + String(event.data ?? ""))
            if (n === "configreloaded") {
                root.checkBlur()
                root._refreshKeyboard()
                root.configReloaded()
            }
            if (n === "focusedmon" && root.focusedMonLosesWorkspace(event.data,
                    Hyprland.workspaces ? Hyprland.workspaces.values ?? [] : []))
                Hyprland.refreshMonitors()
            // only a switch: the pointer crossing to another monitor sends focusedmon too, and coming back closed
            // the popup left open there. A switch that changes monitor still sends workspacev2
            if (n === "workspacev2") root.workspaceActivated(root.focusedMonitor)
            root._layoutTick++
        }
    }

    // silere:menu and silere:tray for Hyprland binds
    readonly property CompositorHyprlandShortcuts _shortcuts: CompositorHyprlandShortcuts {}
    readonly property bool globalShortcuts: root._shortcuts.owns
}
