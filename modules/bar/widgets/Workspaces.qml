pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"

Item {
    id: root

    property bool barActive: true

    required property ShellScreen screen

    readonly property int minVisible: ShellSettings.wsMinVisible
    readonly property int btnW:       26
    readonly property int btnH:       24
    readonly property int _iconSz: 16
    readonly property int gap:        3

    readonly property bool _gemMarker:  ShellSettings.wsActiveMarker === "gem"
    readonly property bool _dotMarker:  ShellSettings.wsActiveMarker === "dot"

    readonly property int effectiveWsCount: Math.max(1, minVisible)
    property int _lastNormalActiveId: 1
    property bool _initialized: false

    implicitWidth:  wsRow.implicitWidth + (urgentOffPage > 0 ? 12 : 0)
    implicitHeight: btnH

    Behavior on implicitWidth { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

    readonly property string monitorName: Compositor.monitorName(root.screen)
    readonly property bool monitorReady: monitorName.length > 0 && Compositor.activeWorkspaceId(monitorName) > 0
    // no hide toggle; `show` exists only so BarContent's per-slot system can treat this like any widget
    readonly property bool show: true
    visible: show
    readonly property int  rawActiveId:  Compositor.activeWorkspaceId(root.monitorName)
    readonly property int  activeId:     rawActiveId > 0 ? rawActiveId : _lastNormalActiveId

    // special/scratchpad shown on this monitor (Hyprland only; niri has no special workspaces)
    readonly property bool inSpecial: Compositor.hasSpecialWorkspaces && Compositor.specialOutput === root.monitorName

    readonly property int groupStart: Math.floor((activeId - 1) / effectiveWsCount) * effectiveWsCount + 1
    readonly property int groupEnd:   groupStart + effectiveWsCount - 1
    readonly property color _trailCoreClear: Qt.rgba(1, 1, 1, 0)

    // wsId → workspace lookup for this monitor, rebuilt on change for O(1) delegate access
    readonly property var _wsMap: {
        const m = {}
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName) m[ws.wsId] = ws
        }
        return m
    }

    function wsObjFor(id) { return root._wsMap[id] ?? null }
    function clearColor(c: color): color { return Qt.rgba(c.r, c.g, c.b, 0) }
    function appsFor(id) { return root._wsApps[id] ?? [] }
    function occupied(id: int): bool {
        const ws = root.wsObjFor(id)
        return (ws !== null && ws.occupied) || root.appsFor(id).length > 0
    }
    function urgent(id: int): bool {
        const ws = root.wsObjFor(id)
        return ws !== null && ws.urgent
    }

    // paging hides urgent workspaces on other pages; surface the first as a tap-to-jump tick beside the row instead of losing the signal
    readonly property int urgentOffPage: {
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName && ws.urgent && ws.wsId > 0
                && (ws.wsId < groupStart || ws.wsId > groupEnd))
                return ws.wsId
        }
        return 0
    }

    // class → icon memo; recomputes only on toplevel-list changes, no polling
    property var _iconCache: ({})
    function _iconForClass(cls: string): string {
        const raw = String(cls || "").trim()
        const key = raw.toLowerCase()
        if (!key) return ""
        if (root._iconCache[key] !== undefined) return root._iconCache[key]
        // try the desktop-entry icon first (zen → zen-browser), then the bare class (kitty),
        // then the final segment for reverse-DNS ids (org.wezfurlong.wezterm → wezterm).
        const de = DesktopEntries.heuristicLookup(raw)
        const tail = key.indexOf(".") >= 0 ? key.split(".").pop() : ""
        const candidates = [de && de.icon, key, tail].filter(Boolean)
        let src = ""
        for (let i = 0; i < candidates.length && !src; i++)
            src = Quickshell.iconPath(candidates[i], true)
        root._iconCache[key] = src
        return src
    }
    // Desktop-entry changes need an explicit cache tick. Compositor owns the
    // single coalesced toplevel refresh, so every monitor reads the same update.
    property int _wsAppsTick: 0
    Connections {
        target: ShellSettings
        function onWsShowAppIconsChanged() {
            // settings flip, not a workspace hop: suppress the gem's move-pulse/glint/trail while the row re-lays out
            root._paging = true
            _pagingReset.restart()
        }
        function onWorkspaceShiftChanged() {
            if (!ShellSettings.workspaceShift) {
                _groupFadeAnim.stop()
                root.opacity = 1
                root._pageShift = 0
            }
        }
    }

    // DesktopEntries loads asynchronously, a class resolved before it's ready
    // (heuristicLookup → null) gets a stale empty cache entry. Drop the cache and
    // recompute once entries land (or a .desktop is installed mid-session).
    Connections {
        target: ShellSettings.wsShowAppIcons ? DesktopEntries : null
        function onApplicationsChanged() {
            root._iconCache = ({})
            root._wsAppsTick++
        }
    }

    // wsId → [{icon,count}] for visible apps. reads each toplevel's *live* workspace, not the stale lastIpcObject,
    readonly property var _wsApps: {
        root._wsAppsTick
        const map = {}
        if (!ShellSettings.wsShowAppIcons) return map
        const seen = {}
        const start = root.groupStart
        const end = root.groupEnd
        const tops = Compositor.toplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName) continue
            const wid = t.wsId ?? 0
            if (wid < start || wid > end) continue
            const rawCls = String(t.appId || "")
            const cls = rawCls.toLowerCase()
            if (!cls) continue
            if (!map[wid]) map[wid] = []
            const key = wid + "|" + cls
            if (seen[key] !== undefined) { map[wid][seen[key]].count++; continue }
            if (map[wid].length >= 3) continue
            const ic = root._iconForClass(rawCls)
            if (!ic) continue
            seen[key] = map[wid].length
            map[wid].push({ icon: ic, count: 1 })
        }
        return map
    }

    function _btnW(wsId: int): int {
        if (ShellSettings.wsShowAppIcons && wsId !== activeId) {
            const apps = root.appsFor(wsId)
            if (apps && apps.length > 0)
                return apps.length * _iconSz + (apps.length - 1) * 4 + 10
        }
        return btnW
    }
    function _diamondX(diamondW: real): real {
        let acc = 0
        const ids = visibleIds
        for (let i = 0; i < ids.length && ids[i] !== activeId; i++)
            acc += _btnW(ids[i]) + gap
        return acc + (_btnW(activeId) - diamondW) / 2
    }

    // A page holds exactly effectiveWsCount workspaces (1-5, 6-10, …).
    readonly property var visibleIds: {
        const ids = []
        for (let id = groupStart; id <= groupEnd; id++) ids.push(id)
        return ids
    }

    readonly property int activeIndex: visibleIds.indexOf(activeId)

    Component.onCompleted: {
        _lastNormalActiveId = activeId
        _prevGroupStart = groupStart
        _initialized = monitorReady
    }

    onRawActiveIdChanged: {
        if (rawActiveId > 0) _lastNormalActiveId = rawActiveId
    }

    onMonitorReadyChanged: {
        if (monitorReady) {
            _lastNormalActiveId = activeId
            _initialized = true
        }
    }

    // while a page flips the new buttons shouldn't each pop in — the group fade carries it; _paging gates the enter anim
    property bool _paging: false
    Timer { id: _pagingReset; interval: Motion.fast + Motion.width; onTriggered: root._paging = false }

    // directional page flip: the new group slides in from the side being moved toward
    property int  _prevGroupStart: 1
    property int  _pageDir:        1
    property real _pageShift:      0
    transform: Translate { x: root._pageShift }

    onGroupStartChanged: {
        const dir = groupStart >= _prevGroupStart ? 1 : -1
        _prevGroupStart = groupStart
        if (!_initialized || !monitorReady) {
            root.opacity = 1
            return
        }
        _pageDir = dir
        _paging = true
        _pagingReset.restart()
        if (ShellSettings.workspaceShift) _groupFadeAnim.restart()
        else root.opacity = 1
    }

    SequentialAnimation {
        id: _groupFadeAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(85);  easing.type: Easing.OutCubic }
        ScriptAction    { script: root._pageShift = root._pageDir * 10 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity";    to: 1; duration: Motion.ms(150); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_pageShift"; to: 0; duration: Motion.ms(165); easing.type: Easing.OutQuart }
        }
    }

    function toRoman(n: int): string {
        if (n < 1 || n > 3999) return String(n)
        const vals = [1000,900,500,400,100,90,50,40,10,9,5,4,1]
        const syms = ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
        let r = ""
        for (let i = 0; i < vals.length; i++)
            while (n >= vals[i]) { r += syms[i]; n -= vals[i] }
        return r
    }

    function activate(id: int): void {
        if (!monitorReady || id < 1 || id === activeId) return
        Compositor.focusWorkspace(id, root.monitorName)
    }

    function _focusWsIndex(index: int): void {
        if (_wsRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_wsRepeater.count - 1, index))
        const item = _wsRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    // the active diamond is the Silere Anchor: tap opens the menu beneath the gem. map the gem centre to screen coords so the panel lines up under it
    function openAnchorMenu(): void {
        const pt = root.mapToItem(null, diamond.x + diamond.width / 2, 0)
        MenuState.toggleAt(pt.x, root.screen)
    }

    function openQuickActions(): void {
        const pt = root.mapToItem(null, diamond.x + diamond.width / 2, 0)
        QuickActionsState.toggleAt(pt.x, root.screen, ShellSettings.barPosition === "bottom")
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.monitorReady && ShellSettings.wsScrollSwitch
        onWheel: (event) => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, "workspaces")
            if (n !== 0) root.activate(root.activeId - n)
        }
    }

    Rectangle {
        id: trail
        readonly property real _head: diamond.x + diamond.width / 2
        readonly property real _tail: diamond._trailX + diamond.width / 2
        readonly property real _gap:  Math.abs(_head - _tail)
        readonly property bool _rightward: _head >= _tail
        readonly property real _strength: (ShellSettings.workspaceShift && !root._paging) ? Math.min(1, _gap / 13) : 0

        height: 4 + _strength * 4
        radius: height / 2
        antialiasing: true
        y: (root.btnH - height) / 2
        x:     Math.min(_head, _tail) - height / 2
        width: _gap + height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: trail._rightward ? root.clearColor(diamond.tint) : diamond.tint }
            GradientStop { position: 1.0; color: trail._rightward ? diamond.tint : root.clearColor(diamond.tint) }
        }
        opacity: _strength * 0.93
        visible: opacity > 0.01
    }

    Rectangle {
        id: trailGlow
        height: 10 + trail._strength * 4
        radius: height / 2
        antialiasing: true
        y: (root.btnH - height) / 2
        x: trail.x
        width: trail.width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: trail._rightward ? root.clearColor(diamond.tint) : diamond.tint }
            GradientStop { position: 1.0; color: trail._rightward ? diamond.tint : root.clearColor(diamond.tint) }
        }
        opacity: trail._strength * 0.20
        visible: opacity > 0.01
    }

    Rectangle {
        id: trailCore
        height: 1.5 + trail._strength * 1.5
        radius: height / 2
        antialiasing: true
        y: (root.btnH - height) / 2
        x: trail.x
        width: trail.width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: trail._rightward ? root._trailCoreClear : Qt.rgba(1, 1, 1, 0.95) }
            GradientStop { position: 1.0; color: trail._rightward ? Qt.rgba(1, 1, 1, 0.95) : root._trailCoreClear }
        }
        opacity: trail._strength * 0.88
        visible: opacity > 0.01
    }

    // No render layer: an FBO fringes the small sprite when scaled. 12px keeps the
    // gem on whole pixels while leaving enough room for the layered facets to
    // render cleanly when the bar is zoomed or screen-scaled.
    Item {
        id: diamond
        width:  root._dotMarker ? 8 : 12
        height: width
        y: (root.btnH - height) / 2
        opacity: root.monitorReady && root.activeIndex >= 0 ? 0.92 : 0
        visible: opacity > 0.01

        readonly property real targetX: root.activeIndex >= 0
            ? root._diamondX(width)
            : 0
        x: targetX

        property real _hoverScale:   1.0
        property real _tapScale:     1.0
        property real _moveScale:    1.0
        property real _specialScale: 1.0
        property real _glint:        -1.15
        property real _trailX:       targetX
        property real _menuOn:    MenuState.open ? 1 : 0
        property real _menuPulse: 0
        Behavior on _menuOn { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(220); easing.type: Easing.OutCubic } }

        readonly property color tint: {
            return root.urgent(root.activeId) ? Theme.warning : Theme.accent
        }
        // animated proxy so _energy stays continuous — every other input already eases, this one would step
        property real _specialOn: root.inSpecial ? 0.65 : 0
        Behavior on _specialOn { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }
        readonly property real _energy: Math.max(diamond._menuOn * (0.70 + diamond._menuPulse * 0.30),
                                                  _specialOn,
                                                  (_hoverScale - 1.0) * 4.2,
                                                  (_tapScale   - 1.0) * 2.2,
                                                  (_moveScale  - 1.0) * 3.0)

        scale: _hoverScale * _tapScale * _moveScale * _specialScale
        transformOrigin: Item.Center

        // ambient aura: wakes for hover/menu/special/move only, so it renders nothing at idle.
        // no Behaviors here — _energy's inputs all ease upstream, downstream ones would just restart every frame
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 14
            height: width
            radius: 4
            rotation: 45
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.34)
            opacity: diamond._energy * 0.22
            scale: 0.70 + diamond._energy * 0.22
            visible: root._gemMarker && opacity > 0.01
        }

        Rectangle {
            id: _menuRipple
            anchors.centerIn: parent
            width:  parent.width + 6
            height: width
            radius: root._gemMarker ? 4 : width / 2
            rotation: root._gemMarker ? 45 : 0
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.5)
            opacity: 0
            scale: 1.0
            transformOrigin: Item.Center
            visible: opacity > 0.01
        }

        // special-workspace frame; filled layers not strokes — 1px rotated borders look uneven on fractional displays
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 16
            height: width
            radius: 4
            rotation: 45
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.20)
            opacity: root.inSpecial ? 0.62 : 0.0
            scale:   root.inSpecial ? 1.0 : 0.76
            transformOrigin: Item.Center
            visible: root._gemMarker && opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(root.inSpecial ? 180 : 130); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(root.inSpecial ? 210 : 130); easing.type: Easing.OutQuart } }
        }
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 8
            height: width
            radius: root._gemMarker ? 3 : width / 2
            rotation: root._gemMarker ? 45 : 0
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.34)
            opacity: root.inSpecial ? 0.96 : 0.0
            scale:   root.inSpecial ? 1.0 : 0.68
            transformOrigin: Item.Center
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(root.inSpecial ? 165 : 120); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(root.inSpecial ? 190 : 120); easing.type: Easing.OutQuart } }
        }

        // filled rim, not a stroke (crisp on fractional displays); dot/ring reuse it as an energy-only halo
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 4
            height: width
            radius: root._gemMarker ? 3 : width / 2
            rotation: root._gemMarker ? 45 : 0
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, MenuState.open ? 0.50 : 0.30)
            opacity: root._gemMarker ? 0.55 + diamond._energy * 0.22 : diamond._energy * 0.60
            scale: 1.0 + diamond._energy * (root._gemMarker ? 0.035 : 0.10)
            visible: opacity > 0.01
            Behavior on color   { ColorAnimation { duration: Motion.ms(150) } }
        }

        Rectangle {
            z: -1
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 2
            width:  parent.width + 5
            height: width
            radius: 4
            rotation: 45
            antialiasing: true
            color: Qt.rgba(0, 0, 0, 0.32)
            opacity: 0.14
            visible: root._gemMarker
        }

        // tint kept separate so the urgent→accent swap still colour-animates
        Rectangle {
            anchors.fill: parent
            radius: root._gemMarker ? 2 : width / 2
            rotation: root._gemMarker ? 45 : 0
            antialiasing: true
            color: diamond.tint
            Behavior on color { ColorAnimation { duration: Motion.ms(150) } }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                antialiasing: true
                visible: root._gemMarker
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.20) }
                }
            }

            Item {
                anchors.fill: parent
                clip: true
                visible: _glintAnim.running && root._gemMarker
                Rectangle {
                    width: 2
                    height: parent.height + 8
                    radius: 1
                    antialiasing: true
                    x: {
                        const t = (diamond._glint + 1.15) / 2.3
                        const p = diamond._glintDir >= 0 ? t : 1 - t
                        return Math.round(p * (parent.width + width)) - width
                    }
                    y: -4
                    rotation: -18
                    color: Qt.rgba(1, 1, 1, 0.48)
                }
            }
        }

        // menu-open: the whole marker charges rather than punching a dark socket — luminance lifts uniformly
        Rectangle {
            anchors.fill: parent
            radius: root._gemMarker ? 2 : width / 2
            rotation: root._gemMarker ? 45 : 0
            antialiasing: true
            color: Qt.rgba(1, 1, 1, 1)
            opacity: diamond._menuOn * (0.16 + diamond._menuPulse * 0.18)
            visible: opacity > 0.01
        }

        // missed-notification badge under DND — popups are suppressed then, so the anchor is the only cue
        Rectangle {
            readonly property bool _show: Notifications.effectiveDnd && Notifications.missedCount > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top:       parent.top
            anchors.topMargin: -1
            width:  4
            height: 4
            radius: width / 2
            antialiasing: true
            color: Theme.error
            opacity: _show ? 1 : 0
            scale:   _show ? 1 : 0.2
            transformOrigin: Item.Center
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(150); easing.type: Easing.OutCubic } }
        }

        SequentialAnimation {
            id: _specialPulse
            NumberAnimation { target: diamond; property: "_specialScale"; to: 1.055; duration: Motion.ms(90);  easing.type: Easing.OutCubic }
            NumberAnimation { target: diamond; property: "_specialScale"; to: 1.0;   duration: Motion.ms(185); easing.type: Easing.OutQuart }
        }
        // 1 = sweep left→right, -1 = right→left; captured at glint start so the shimmer flows with the gem's travel
        property int _glintDir: 1
        SequentialAnimation {
            id: _glintAnim
            ScriptAction { script: {
                diamond._glintDir = (diamond.targetX >= diamond.x) ? 1 : -1
                diamond._glint = -1.15
            } }
            NumberAnimation { target: diamond; property: "_glint"; to: 1.15; duration: Motion.ms(260); easing.type: Easing.OutCubic }
            ScriptAction { script: diamond._glint = -1.15 }
        }
        Connections {
            target: root
            enabled: !ShellSettings.reduceMotion
            function onInSpecialChanged() {
                if (!root.inSpecial) return
                _specialPulse.restart()
                if (root._gemMarker) _glintAnim.restart()
            }
        }

        Behavior on x           { enabled: ShellSettings.workspaceShift && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(190); easing.type: Easing.OutQuart } }
        Behavior on opacity     { NumberAnimation { duration: Motion.ms(150) } }
        Behavior on _hoverScale { NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
        Behavior on _trailX     { enabled: ShellSettings.workspaceShift && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutQuart } }

        onTargetXChanged: {
            if (!root.monitorReady) return
            if (root._paging) return
            if (Math.abs(targetX - x) < 2) return
            if (!ShellSettings.workspaceShift || ShellSettings.reduceMotion) return
            _moveAnim.restart()
            if (root._gemMarker) _glintAnim.restart()
        }

        SequentialAnimation {
            id: _moveAnim
            NumberAnimation { target: diamond; property: "_moveScale"; to: 1.08; duration: Motion.ms(65);  easing.type: Easing.OutQuad }
            NumberAnimation { target: diamond; property: "_moveScale"; to: 1.0;  duration: Motion.ms(140); easing.type: Easing.OutCubic }
        }

        SequentialAnimation {
            id: _tapPulse
            NumberAnimation { target: diamond; property: "_tapScale"; to: 1.14; duration: Motion.ms(70);  easing.type: Easing.OutQuad }
            NumberAnimation { target: diamond; property: "_tapScale"; to: 1.0;  duration: Motion.ms(145); easing.type: Easing.OutCubic }
        }

        ParallelAnimation {
            id: _menuRippleAnim
            NumberAnimation { target: _menuRipple; property: "scale";   from: 0.9;  to: 2.7; duration: Motion.ms(540); easing.type: Easing.OutCubic }
            NumberAnimation { target: _menuRipple; property: "opacity"; from: 0.55; to: 0;   duration: Motion.ms(540); easing.type: Easing.OutCubic }
        }
        PulseLoop {
            id: _breathAnim
            running: MenuState.open && !ShellSettings.reduceMotion && !Idle.isIdle
            target: diamond; targetProperty: "_menuPulse"
            peak: 1; floor: 0; restValue: 0
            duration: Motion.ms(950)
        }
        Connections {
            target: MenuState
            enabled: !ShellSettings.reduceMotion
            function onOpenChanged() { if (MenuState.open) _menuRippleAnim.restart() }
        }
    }

    Row {
        id: wsRow
        spacing: root.gap

        Repeater {
            id: _wsRepeater
            model: root.visibleIds

            Item {
                id: ws
                required property int modelData
                required property int index
                readonly property int  wsId:    modelData
                readonly property bool active:  root.monitorReady && root.activeId === wsId
                readonly property var  apps:    root.appsFor(wsId)
                readonly property bool occupied: root.occupied(wsId)
                readonly property bool urgent:  root.urgent(wsId)
                readonly property bool hovered: _hover.hovered
                // gated separately from `hovered` so hover scale/color/tint respect the barHoverHighlight setting (default off)
                readonly property bool _hoverFx: hovered && ShellSettings.barHoverHighlight
                readonly property bool _showIcons: ShellSettings.wsShowAppIcons && !active && apps.length > 0

                width:   root._btnW(wsId)
                height:  root.btnH
                opacity: 1
                scale:   1.0

                // not gated on wsShowAppIcons: disabling it must glide the collapse too, not snap while the gem animates
                Behavior on width {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
                }

                activeFocusOnTab: root.monitorReady

                Component.onCompleted: {
                    _dotFade = active ? 0 : 1
                    if (!root._initialized || ShellSettings.reduceMotion || root._paging) return
                    scale = 0
                    _enterAnim.start()
                }

                SequentialAnimation {
                    id: _enterAnim
                    NumberAnimation { target: ws; property: "scale"; to: 1.0; duration: Motion.ms(130); easing.type: Easing.OutCubic }
                }

                // ack for middle-click "move window here" — the move itself is invisible (window lands on a background ws)
                SequentialAnimation {
                    id: _dropPulse
                    NumberAnimation { target: ws; property: "scale"; to: 1.12; duration: Motion.ms(70);  easing.type: Easing.OutQuad  }
                    NumberAnimation { target: ws; property: "scale"; to: 1.0;  duration: Motion.ms(145); easing.type: Easing.OutCubic }
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + wsId
                Accessible.description: active ? "Current workspace"
                    : urgent ? "Urgent workspace"
                    : occupied ? "Occupied workspace"
                    : "Empty workspace"
                Accessible.focusable: root.monitorReady

                function _activateFromKeyboard(): void {
                    if (!root.monitorReady) return
                    if (ws.active) {
                        _tapPulse.restart()
                        if (!ShellSettings.reduceMotion && root._gemMarker) _glintAnim.restart()
                        root.openAnchorMenu()
                    } else {
                        root.activate(ws.wsId)
                    }
                }

                Keys.onSpacePressed: event => {
                    if (!event.isAutoRepeat) ws._activateFromKeyboard()
                    event.accepted = true
                }
                Keys.onReturnPressed: event => {
                    if (!event.isAutoRepeat) ws._activateFromKeyboard()
                    event.accepted = true
                }
                Keys.onEnterPressed: event => {
                    if (!event.isAutoRepeat) ws._activateFromKeyboard()
                    event.accepted = true
                }
                Keys.onLeftPressed:  event => { root._focusWsIndex(ws.index - 1); event.accepted = true }
                Keys.onRightPressed: event => { root._focusWsIndex(ws.index + 1); event.accepted = true }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        root._focusWsIndex(0)
                        event.accepted = true
                    } else if (event.key === Qt.Key_End) {
                        root._focusWsIndex(_wsRepeater.count - 1)
                        event.accepted = true
                    }
                }

                HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, root.btnW)
                    height: root.btnH
                    radius: height / 2
                    antialiasing: true
                    color: Theme.withAlpha(Theme.accent, 0.10)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent, 0.72)
                    opacity: ws.activeFocus ? 1.0 : 0.0
                    visible: opacity > 0.001
                    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onTapped: (eventPoint, button) => {
                        if (button === Qt.MiddleButton) {
                            // No focused window means nothing moves — don't fake an ack.
                            if (!Compositor.activeToplevel) return
                            Compositor.moveActiveToWorkspace(ws.wsId)
                            if (!ShellSettings.reduceMotion) _dropPulse.restart()
                            return
                        }
                        // right-click belongs to the anchor: quick actions on the active marker, never a switch
                        if (button === Qt.RightButton) {
                            if (ws.active) {
                                _tapPulse.restart()
                                if (!ShellSettings.reduceMotion && root._gemMarker) _glintAnim.restart()
                                root.openQuickActions()
                            }
                            return
                        }
                        if (ws.active) {
                            _tapPulse.restart()
                            if (!ShellSettings.reduceMotion && root._gemMarker) _glintAnim.restart()
                            root.openAnchorMenu()
                        } else {
                            root.activate(ws.wsId)
                        }
                    }
                }

                onHoveredChanged: { if (active) diamond._hoverScale = _hoverFx ? 1.10 : 1.0 }
                onActiveChanged: {
                    diamond._hoverScale = (active && _hoverFx) ? 1.10 : 1.0
                    if (ShellSettings.reduceMotion) { _dotFade = active ? 0 : 1; return }
                    _dotFadeOut.stop(); _dotFadeIn.stop()
                    if (active) _dotFadeOut.restart()
                    else        _dotFadeIn.restart()
                }

                readonly property real _pulseOpacity: _urgentFx.item ? _urgentFx.item.pulseOpacity : 1.0
                readonly property real _shakeX: _urgentFx.item ? _urgentFx.item.shakeX : 0
                property real _dotFade: 1.0
                // dot mode tells you nothing about which ws you'd jump to; hover swaps the dot for its number
                readonly property bool _hoverReveal: ShellSettings.valuesOnHover && hovered
                    && !active && !ShellSettings.wsShowNumbers && !_showIcons
                property real _revealAmt: _hoverReveal ? 1 : 0
                Behavior on _revealAmt { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                property real _dotAlpha: urgent ? 0.95 : occupied ? 0.65 : 0.28
                Behavior on _dotAlpha { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

                Loader {
                    anchors.fill: parent
                    z: -1
                    active: ShellSettings.wsNotifPulse
                    sourceComponent: Component {
                        WorkspaceNotifPulse { workspaceId: ws.wsId }
                    }
                }
                Connections {
                    target: ShellSettings
                    // resync the shared diamond if the setting flips while this ws is active + hovered
                    // (onHoveredChanged/onActiveChanged won't fire on their own here)
                    function onBarHoverHighlightChanged() {
                        if (ws.active) diamond._hoverScale = ws._hoverFx ? 1.10 : 1.0
                    }
                }
                NumberAnimation {
                    id: _dotFadeOut
                    target: ws; property: "_dotFade"; to: 0
                    duration: Motion.ms(120); easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    id: _dotFadeIn
                    PauseAnimation  { duration: Motion.ms(150) }
                    NumberAnimation { target: ws; property: "_dotFade"; to: 1; duration: Motion.ms(220); easing.type: Easing.OutCubic }
                }

                Loader {
                    id: _urgentFx
                    active: ws.urgent && !ws.active
                    sourceComponent: Component {
                        WorkspaceUrgentFx { barActive: root.barActive }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    transform: Translate { x: ws._shakeX }
                    text:    ShellSettings.wsRomanNumerals ? root.toRoman(ws.wsId) : ws.wsId
                    opacity: !ws._showIcons
                        ? Math.max(ShellSettings.wsShowNumbers ? 1 : 0, ws._revealAmt)
                          * (ws.active ? 0 : 1) * ws._pulseOpacity * ShellSettings.wsMarkerOpacity
                        : 0
                    scale:   ws.active ? 0.6 : (ws._hoverFx ? 1.12 : 1)
                    color:   ws.urgent
                        ? Theme.warning
                        : (ws.occupied
                            ? (ws._hoverFx ? Theme.accent : Theme.withAlpha(Theme.text, 0.85))
                            : (ws._hoverFx ? Theme.withAlpha(Theme.accent, 0.65) : Theme.withAlpha(Theme.subtext, 0.45)))
                    font.pixelSize: Settings.fontSize - 1
                    font.family:    Settings.font
                    renderType:     Text.NativeRendering

                    Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                    Behavior on scale   { NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                    Behavior on color   { ColorAnimation  { duration: Motion.color } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    transform: Translate { x: ws._shakeX }
                    width:  ws.urgent ? 6 : (ws.occupied ? 5 : 4)
                    height: width
                    radius: width / 2
                    antialiasing: true
                    visible: !ShellSettings.wsShowNumbers && !ws._showIcons
                    opacity: (1 - ws._revealAmt) * ws._dotFade * (ws._hoverFx && !ws.urgent
                             ? Math.min(1, ws._dotAlpha + 0.18)
                             : ws._dotAlpha) * ws._pulseOpacity * ShellSettings.wsMarkerOpacity
                    color: ws.urgent ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85)
                    scale: ws._hoverFx ? 1.2 : 1.0

                    Behavior on color { ColorAnimation { duration: Motion.color } }
                    Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                }

                Loader {
                    anchors.centerIn: parent
                    transform: Translate { x: ws._shakeX }
                    active: ws._showIcons
                    sourceComponent: Component {
                        WorkspaceAppIcons {
                            apps: ws.apps
                            iconSize: root._iconSz
                            hoverFx: ws._hoverFx
                            pulseOpacity: ws._pulseOpacity
                        }
                    }
                }
            }
        }
    }

    Item {
        id: _urgentTick
        readonly property bool shown: root.urgentOffPage > 0
        // Hold the last id while fading out so the jump target doesn't blank mid-tap.
        property int targetWs: 0
        readonly property int _live: root.urgentOffPage
        on_LiveChanged: if (_live > 0) {
            if (targetWs !== _live) _pulseSettled = false
            targetWs = _live
        }
        Component.onCompleted: if (_live > 0) targetWs = _live

        x: wsRow.implicitWidth + 2
        width: 10
        height: root.btnH
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

        activeFocusOnTab: shown
        Accessible.role: Accessible.Button
        Accessible.name: "Urgent workspace " + targetWs
        Accessible.description: "Activate to jump to it."

        function _jump(): void { if (shown) root.activate(targetWs) }
        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _urgentTick._jump(); event.accepted = true }
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _urgentTick._jump(); event.accepted = true }
        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _urgentTick._jump(); event.accepted = true }

        HoverHandler { id: _tickHover; enabled: _urgentTick.shown; cursorShape: Qt.PointingHandCursor }
        TapHandler   { enabled: _urgentTick.shown; onTapped: _urgentTick._jump() }

        property real _pulse: 1.0
        property bool _pulseSettled: false
        onShownChanged: if (shown) _pulseSettled = false
        SequentialAnimation {
            running: _urgentTick.shown && !_urgentTick._pulseSettled
                && root.barActive && !ShellSettings.reduceMotion && !Idle.isIdle
            loops:   Animation.Infinite
            onRunningChanged: if (!running) _urgentTick._pulse = 1.0
            NumberAnimation { target: _urgentTick; property: "_pulse"; to: 0.35; duration: Motion.ms(550); easing.type: Easing.InOutSine }
            NumberAnimation { target: _urgentTick; property: "_pulse"; to: 1.0;  duration: Motion.ms(550); easing.type: Easing.InOutSine }
        }
        Timer {
            interval: 15000
            running: _urgentTick.shown && !_urgentTick._pulseSettled && !Idle.isIdle
            onTriggered: _urgentTick._pulseSettled = true
        }

        Rectangle {
            anchors.centerIn: parent
            width:  5
            height: 5
            radius: 2.5
            antialiasing: true
            color: Theme.warning
            opacity: _urgentTick._pulse * ((_tickHover.hovered || _urgentTick.activeFocus) ? 1.0 : 0.9)
            scale: (_tickHover.hovered && ShellSettings.barHoverHighlight) || _urgentTick.activeFocus ? 1.25 : 1.0
            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }
    }
}
