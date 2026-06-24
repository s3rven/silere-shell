import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import "../../../config"
import "../../../services"

Item {
    id: root

    required property ShellScreen screen

    readonly property int minVisible: ShellSettings.wsMinVisible
    readonly property int btnW:       26
    readonly property int btnH:       24
    readonly property int _iconSz: ShellSettings.wsIconSize
    readonly property int gap:        3

    readonly property int effectiveWsCount: Math.max(1, minVisible)
    property int _lastNormalActiveId: 1
    property bool _initialized: false

    implicitWidth:  wsRow.implicitWidth
    implicitHeight: btnH

    Behavior on implicitWidth { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

    readonly property HyprlandMonitor monitor:    Hyprland.monitorFor(root.screen)
    readonly property bool monitorReady: monitor !== null && monitor.activeWorkspace !== null
    readonly property int  rawActiveId:  monitor?.activeWorkspace?.id ?? _lastNormalActiveId
    readonly property int  activeId:     rawActiveId > 0 ? rawActiveId : _lastNormalActiveId

    // Whether a special/scratchpad workspace (super+S) is shown on this monitor.
    // monitor.activeWorkspace stays on the *normal* ws when a special is open (and
    // Quickshell exposes no special field), so we track Hyprland's activespecial
    // event below instead. Starts false; correct after the first toggle.
    property bool inSpecial: false

    readonly property int groupStart: Math.floor((activeId - 1) / effectiveWsCount) * effectiveWsCount + 1
    readonly property int groupEnd:   groupStart + effectiveWsCount - 1

    // id → workspace lookup, rebuilt on change for O(1) delegate access
    readonly property var _wsMap: {
        const m = {}
        const vals = Hyprland.workspaces.values ?? []
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws) m[ws.id] = ws
        }
        return m
    }

    function wsObjFor(id) { return root._wsMap[id] ?? null }

    // Per-workspace app icons (only when wsShowAppIcons is on). Window class →
    // desktop-entry icon, memoised so each class resolves once. Recomputes only
    // when Hyprland's toplevel list changes, no polling.
    property var _iconCache: ({})
    function _iconForClass(cls: string): string {
        const key = String(cls || "").toLowerCase()
        if (!key) return ""
        if (root._iconCache[key] !== undefined) return root._iconCache[key]
        // Try the desktop-entry icon first (zen → zen-browser), then the bare
        // class (kitty → kitty); take whichever actually exists in the theme.
        const de = DesktopEntries.heuristicLookup(cls)
        const candidates = (de && de.icon) ? [de.icon, key] : [key]
        let src = ""
        for (let i = 0; i < candidates.length && !src; i++)
            src = Quickshell.iconPath(candidates[i], true)
        root._iconCache[key] = src
        return src
    }
    // Window list changes (valuesChanged) don't fire on workspace *moves*, so
    // bump a tick on the relevant Hyprland events and refresh the toplevels.
    // Compositor events arrive in bursts (one window open fires several); while a
    // settle window is in flight, fold further events into one trailing refresh
    // instead of issuing an IPC refresh per event.
    property int _wsAppsTick: 0
    property bool _wsAppsRepeat: false
    function _refreshWorkspaceApps(): void {
        if (!ShellSettings.wsShowAppIcons) return
        if (_wsAppsInvalidate.running) { _wsAppsRepeat = true; return }
        Hyprland.refreshToplevels()
        _wsAppsInvalidate.restart()
    }
    // Delay the recompute so refreshToplevels() has time to settle, bumping
    // _wsAppsTick immediately would recompute _wsApps against stale workspace data.
    Timer {
        id: _wsAppsInvalidate
        interval: 80
        repeat: false
        onTriggered: {
            root._wsAppsTick++
            if (root._wsAppsRepeat) { root._wsAppsRepeat = false; root._refreshWorkspaceApps() }
        }
    }
    Timer {
        id: _initialAppsRefresh
        interval: 250
        onTriggered: root._refreshWorkspaceApps()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            // Special/scratchpad open/close for this monitor. Data is
            // "[id,]wsname,monitor", a non-empty wsname before the monitor means a
            // special is shown there; empty means it closed.
            if (n === "activespecial" || n === "activespecialv2") {
                const parts = String(event.data ?? "").split(",")
                if (parts.length < 2 || !root.monitor) return
                if (parts[parts.length - 1] !== root.monitor.name) return
                root.inSpecial = String(parts[parts.length - 2]).length > 0
                return
            }
            // Window list changes don't fire on workspace *moves*, so refresh on these.
            if (ShellSettings.wsShowAppIcons &&
                (n === "openwindow" || n === "closewindow" || n === "movewindowv2"))
                root._refreshWorkspaceApps()
        }
    }
    Connections {
        target: ShellSettings
        function onWsShowAppIconsChanged() {
            if (ShellSettings.wsShowAppIcons) _initialAppsRefresh.restart()
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
        target: DesktopEntries
        enabled: ShellSettings.wsShowAppIcons
        function onApplicationsChanged() {
            root._iconCache = ({})
            root._wsAppsTick++
        }
    }

    // wsId → [{ icon, count }] for visible apps. Reads each toplevel's *live*
    // workspace (reactive), not the stale lastIpcObject, and dedupes repeats
    // of the same app into one icon with a count. Up to 3 distinct apps.
    readonly property var _wsApps: {
        root._wsAppsTick
        const map = {}
        if (!ShellSettings.wsShowAppIcons) return map
        const seen = {}
        const start = root.groupStart
        const end = root.groupEnd
        const tops = Hyprland.toplevels ? (Hyprland.toplevels.values ?? []) : []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t) continue
            const o   = t.lastIpcObject
            const wid = t.workspace?.id ?? o?.workspace?.id ?? 0
            if (wid < start || wid > end) continue
            const rawCls = String((t.wayland && t.wayland.appId)
                                  || (o && (o.class || o.initialClass)) || "")
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

    // Per-button width: an inactive workspace with app icons grows to fit them;
    // the diamond/trail track this.
    function _btnW(wsId: int): int {
        if (ShellSettings.wsShowAppIcons && wsId !== activeId) {
            const apps = _wsApps[wsId]
            if (apps && apps.length > 0)
                return apps.length * _iconSz + (apps.length - 1) * 4 + 10
        }
        return btnW
    }
    // Sum the widths of the buttons before the active one, then centre in it.
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
        if (ShellSettings.wsShowAppIcons) _initialAppsRefresh.restart()
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

    // While a page flips, the new page's buttons shouldn't each pop in, the
    // group fade (onGroupStartChanged) carries it; _paging gates the enter anim.
    property bool _paging: false
    Timer { id: _pagingReset; interval: Motion.fast + Motion.width; onTriggered: root._paging = false }

    // Directional page flip: the new group slides in from the side being moved
    // toward (next page from the right, previous from the left), not just a
    // fade-in-place, so the flip reads as travel.
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
        HyprActions.focusWorkspace(id, monitor?.name ?? "")
    }

    // The active diamond is the Silere Anchor: a tap opens the menu beneath the
    // gem. Map the gem centre to screen coords so the panel lines up under it.
    function openAnchorMenu(): void {
        const pt = root.mapToItem(null, diamond.x + diamond.width / 2, 0)
        MenuState.toggleAt(pt.x, root.screen)
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
            GradientStop { position: 0.0; color: trail._rightward ? "transparent" : diamond.tint }
            GradientStop { position: 1.0; color: trail._rightward ? diamond.tint : "transparent" }
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
            GradientStop { position: 0.0; color: trail._rightward ? "transparent" : diamond.tint }
            GradientStop { position: 1.0; color: trail._rightward ? diamond.tint : "transparent" }
        }
        opacity: trail._strength * 0.20
        visible: opacity > 0.01
    }

    Rectangle {
        id: trailCore
        // Scales with the same ratio as `trail` (height/4 at rest, height/8 at
        // full strength) so the bright core stays proportional to the band it
        // sits inside instead of reading thicker on short hops than long ones.
        height: 1.5 + trail._strength * 1.5
        radius: height / 2
        antialiasing: true
        y: (root.btnH - height) / 2
        x: trail.x
        width: trail.width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: trail._rightward ? "transparent" : Qt.rgba(1, 1, 1, 0.95) }
            GradientStop { position: 1.0; color: trail._rightward ? Qt.rgba(1, 1, 1, 0.95) : "transparent" }
        }
        opacity: trail._strength * 0.88
        visible: opacity > 0.01
    }

    // No render layer: an FBO fringes the small sprite when scaled. 12px keeps the
    // gem on whole pixels while leaving enough room for the layered facets to
    // render cleanly when the bar is zoomed or screen-scaled.
    Item {
        id: diamond
        width:  12
        height: 12
        y: (root.btnH - height) / 2
        opacity: root.monitorReady && root.activeIndex >= 0 ? 0.92 : 0
        visible: opacity > 0.01

        readonly property real targetX: root.activeIndex >= 0
            ? root._diamondX(width)
            : x
        x: targetX

        property real _hoverScale:   1.0
        property real _tapScale:     1.0
        property real _moveScale:    1.0
        property real _specialScale: 1.0
        property real _glint:        -1.15
        property real _trailX:       targetX

        readonly property color tint: {
            const ws = root.wsObjFor(root.activeId)
            return (ws && ws.urgent) ? Theme.warning : Theme.accent
        }
        readonly property real _energy: Math.max(MenuState.open ? 0.9 : 0,
                                                  root.inSpecial ? 0.65 : 0,
                                                  (_hoverScale - 1.0) * 4.2,
                                                  (_tapScale   - 1.0) * 2.2,
                                                  (_moveScale  - 1.0) * 3.0)

        scale: _hoverScale * _tapScale * _moveScale * _specialScale
        transformOrigin: Item.Center

        // ── Silere anchor ─────────────────────────────────────────────────────
        // Ambient aura: only really wakes up for hover/menu/special/move, so the
        // active workspace keeps a premium "gem" feel without turning into a blob.
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 14
            height: width
            radius: 4
            rotation: 45
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.34)
            opacity: 0.06 + diamond._energy * 0.16
            scale: 0.70 + diamond._energy * 0.22
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(130); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(170); easing.type: Easing.OutCubic } }
        }

        // Special/scratchpad (super+S): a translucent accent diamond frames the
        // gem to say "special". Filled layers, not strokes: they stay centred and
        // crisp on fractional displays where 1px rotated borders look uneven.
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
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(root.inSpecial ? 180 : 130); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(root.inSpecial ? 210 : 130); easing.type: Easing.OutQuart } }
        }
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 8
            height: width
            radius: 3
            rotation: 45
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, 0.34)
            opacity: root.inSpecial ? 0.96 : 0.0
            scale:   root.inSpecial ? 1.0 : 0.68
            transformOrigin: Item.Center
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(root.inSpecial ? 165 : 120); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(root.inSpecial ? 190 : 120); easing.type: Easing.OutQuart } }
        }

        // Outer rim, filled behind the body rather than stroked. It gives the gem
        // a crisp edge on fractional displays and doubles as a subtle menu anchor.
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 4
            height: width
            radius: 3
            rotation: 45
            antialiasing: true
            color: Theme.withAlpha(diamond.tint, MenuState.open ? 0.50 : 0.30)
            opacity: 0.55 + diamond._energy * 0.22
            scale: 1.0 + diamond._energy * 0.035
            visible: opacity > 0.01
            Behavior on color   { ColorAnimation { duration: Motion.ms(150) } }
            Behavior on opacity { NumberAnimation { duration: Motion.ms(130); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(150); easing.type: Easing.OutCubic } }
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
        }

        // Body — the gem. Solid tint under a gentle gloss; the tint stays separate
        // so the urgent→accent swap still colour-animates.
        Rectangle {
            anchors.fill: parent
            radius: 2
            rotation: 45
            antialiasing: true
            color: diamond.tint
            Behavior on color { ColorAnimation { duration: Motion.ms(150) } }

            // Soft crown→pavilion sheen for a little depth. One smooth gradient —
            // no seam, no hairline — kept subtle so the gem reads as solid accent.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.20) }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width:  parent.width - 5
                height: parent.height - 5
                radius: 1
                antialiasing: true
                color: Qt.rgba(1, 1, 1, 0.10)
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 2
                width: parent.width - 5
                height: 2
                radius: 1
                antialiasing: true
                color: Qt.rgba(1, 1, 1, 0.26)
            }
            Item {
                anchors.fill: parent
                clip: true
                visible: _glintAnim.running
                Rectangle {
                    width: 2
                    height: parent.height + 8
                    radius: 1
                    antialiasing: true
                    x: Math.round((diamond._glint + 1.15) / 2.3 * (parent.width + width)) - width
                    y: -4
                    rotation: -18
                    color: Qt.rgba(1, 1, 1, 0.48)
                }
            }
        }

        // Menu-open state: a small dark socket opens dead-centre while the Silere
        // menu is showing, so the anchor reads as engaged. Surface-coloured (never
        // white); the gem is otherwise solid.
        Rectangle {
            anchors.centerIn: parent
            width:  4
            height: 4
            radius: 1
            rotation: 45
            antialiasing: true
            color: Theme.surface
            opacity: MenuState.open ? 0.92 : 0
            scale:   MenuState.open ? 1.0 : 0.45
            transformOrigin: Item.Center
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(140); easing.type: Easing.OutCubic } }
        }

        // Attention badge: a static dot on the crown when notifications were missed
        // while Do-Not-Disturb is on (otherwise the popups are suppressed and the
        // anchor is the only cue). No pulse, no border — the menu carries detail.
        Rectangle {
            readonly property bool _show: Notifications.dnd && Notifications.missedCount > 0
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

        // A quick settle-pop when entering a special workspace, so the frame's
        // entrance lands with a beat instead of just appearing.
        SequentialAnimation {
            id: _specialPulse
            NumberAnimation { target: diamond; property: "_specialScale"; to: 1.055; duration: Motion.ms(90);  easing.type: Easing.OutCubic }
            NumberAnimation { target: diamond; property: "_specialScale"; to: 1.0;   duration: Motion.ms(185); easing.type: Easing.OutQuart }
        }
        SequentialAnimation {
            id: _glintAnim
            ScriptAction { script: diamond._glint = -1.15 }
            NumberAnimation { target: diamond; property: "_glint"; to: 1.15; duration: Motion.ms(260); easing.type: Easing.OutCubic }
            ScriptAction { script: diamond._glint = -1.15 }
        }
        Connections {
            target: root
            enabled: !ShellSettings.reduceMotion
            function onInSpecialChanged() {
                if (!root.inSpecial) return
                _specialPulse.restart()
                _glintAnim.restart()
            }
        }

        // Fixed duration with no bounce: the trail gives movement, the gem lands crisp.
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
            _glintAnim.restart()
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
    }

    Row {
        id: wsRow
        spacing: root.gap

        Repeater {
            model: root.visibleIds

            Item {
                id: ws
                required property int modelData
                readonly property int  wsId:    modelData
                readonly property bool active:  root.monitorReady && root.activeId === wsId
                readonly property var  wsObj:   root.wsObjFor(wsId)
                readonly property bool exists:  wsObj !== null
                readonly property bool urgent:  exists && wsObj.urgent
                readonly property bool hovered: _hover.hovered
                // App icons shown on inactive occupied workspaces (the active one
                // keeps its diamond). Empty/active fall back to the number/dot.
                readonly property var  _apps:      root._wsApps[wsId] ?? []
                readonly property bool _showIcons: ShellSettings.wsShowAppIcons && !active && _apps.length > 0

                width:   root._btnW(wsId)
                height:  root.btnH
                opacity: 1
                scale:   1.0

                Behavior on width {
                    enabled: ShellSettings.wsShowAppIcons && !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
                }

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

                // Ack for middle-click "move window here" — the move itself is
                // invisible (the window lands on a background workspace).
                SequentialAnimation {
                    id: _dropPulse
                    NumberAnimation { target: ws; property: "scale"; to: 1.12; duration: Motion.ms(70);  easing.type: Easing.OutQuad  }
                    NumberAnimation { target: ws; property: "scale"; to: 1.0;  duration: Motion.ms(145); easing.type: Easing.OutCubic }
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + wsId
                Accessible.description: active ? "Current workspace" : (exists ? "Switch to workspace" : "Empty workspace")

                HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onTapped: (eventPoint, button) => {
                        if (button === Qt.MiddleButton) {
                            HyprActions.moveActiveToWorkspace(ws.wsId)
                            if (!ShellSettings.reduceMotion) _dropPulse.restart()
                            return
                        }
                        // Right-click is the anchor's own gesture: only the active
                        // diamond claims it (→ menu for now, quick-actions later);
                        // on inactive workspaces it's inert, never a switch.
                        if (button === Qt.RightButton) {
                            if (ws.active) {
                                _tapPulse.restart()
                                if (!ShellSettings.reduceMotion) _glintAnim.restart()
                                root.openAnchorMenu()
                            }
                            return
                        }
                        if (ws.active) {
                            _tapPulse.restart()
                            if (!ShellSettings.reduceMotion) _glintAnim.restart()
                            root.openAnchorMenu()
                        } else {
                            root.activate(ws.wsId)
                        }
                    }
                }

                onHoveredChanged: { if (active) diamond._hoverScale = hovered ? 1.10 : 1.0 }
                onActiveChanged: {
                    diamond._hoverScale = (active && hovered) ? 1.10 : 1.0
                    if (ShellSettings.reduceMotion) { _dotFade = active ? 0 : 1; return }
                    _dotFadeOut.stop(); _dotFadeIn.stop()
                    if (active) _dotFadeOut.restart()
                    else        _dotFadeIn.restart()
                }

                property real _pulseOpacity: 1.0
                property real _shakeX:       0
                property real _dotFade: 1.0
                property real _dotAlpha: urgent ? 0.95 : exists ? 0.65 : 0.28
                Behavior on _dotAlpha { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

                // Notification-source pulse: a soft accent (or error) wash behind
                // the workspace when a notification arrives from a window on it.
                property real _notifPulse: 0
                property bool _notifPulseCritical: false
                Rectangle {
                    anchors.centerIn: parent
                    width: root.btnH; height: root.btnH
                    radius: root.btnH / 2
                    antialiasing: true
                    z: -1
                    color: ws._notifPulseCritical ? Theme.error : Theme.accent
                    opacity: ws._notifPulse * 0.10
                    visible: ShellSettings.wsNotifPulse && opacity > 0.01
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14
                    radius: 7
                    antialiasing: true
                    z: -1
                    color: ws._notifPulseCritical ? Theme.error : Theme.accent
                    opacity: ws._notifPulse * 0.22
                    visible: ShellSettings.wsNotifPulse && opacity > 0.01
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 7; height: 7
                    radius: 3.5
                    antialiasing: true
                    z: -1
                    color: ws._notifPulseCritical ? Theme.error : Theme.accent
                    opacity: ws._notifPulse * 0.50
                    visible: ShellSettings.wsNotifPulse && opacity > 0.01
                }
                Connections {
                    target: Notifications
                    enabled: ShellSettings.wsNotifPulse && !ShellSettings.reduceMotion
                    function onSourcePulse(wsId, critical) {
                        if (wsId !== ws.wsId) return
                        ws._notifPulseCritical = critical
                        _notifPulseAnim.restart()
                    }
                }
                Connections {
                    target: ShellSettings
                    function onReduceMotionChanged() {
                        if (ShellSettings.reduceMotion) {
                            _notifPulseAnim.stop()
                            ws._notifPulse = 0
                        }
                    }
                }
                SequentialAnimation {
                    id: _notifPulseAnim
                    NumberAnimation { target: ws; property: "_notifPulse"; to: 1.0; duration: Motion.ms(150);  easing.type: Easing.OutQuad }
                    NumberAnimation { target: ws; property: "_notifPulse"; to: 0.0; duration: Motion.ms(1100); easing.type: Easing.OutCubic }
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

                SequentialAnimation {
                    running: ws.urgent && !ws.active && !ShellSettings.reduceMotion && !Idle.isIdle
                    loops:   Animation.Infinite
                    onRunningChanged: if (!running) { ws._pulseOpacity = 1.0; ws._shakeX = 0 }
                    NumberAnimation { target: ws; property: "_shakeX"; to:  2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad  }
                    NumberAnimation { target: ws; property: "_shakeX"; to: -2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad  }
                    NumberAnimation { target: ws; property: "_shakeX"; to:  2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad  }
                    NumberAnimation { target: ws; property: "_shakeX"; to:  0;   duration: Motion.ms(55); easing.type: Easing.OutCubic }
                    // Slow opacity pulse, affects both number text and dot
                    NumberAnimation { target: ws; property: "_pulseOpacity"; to: 0.3; duration: Motion.ms(550); easing.type: Easing.InOutSine }
                    NumberAnimation { target: ws; property: "_pulseOpacity"; to: 1.0; duration: Motion.ms(550); easing.type: Easing.InOutSine }
                }

                Text {
                    anchors.centerIn: parent
                    transform: Translate { x: ws._shakeX }
                    text:    ShellSettings.wsRomanNumerals ? root.toRoman(ws.wsId) : ws.wsId
                    opacity: (ShellSettings.wsShowNumbers && !ws._showIcons) ? (ws.active ? 0 : 1) * ws._pulseOpacity : 0
                    // hover lift matches the dot (1.2) and app-icon (1.08) modes
                    scale:   ws.active ? 0.6 : (ws.hovered ? 1.12 : 1)
                    color:   ws.urgent
                        ? Theme.warning
                        : (ws.exists
                            ? (ws.hovered ? Theme.accent : Theme.withAlpha(Theme.text, 0.85))
                            : (ws.hovered ? Theme.withAlpha(Theme.accent, 0.65) : Theme.withAlpha(Theme.subtext, 0.45)))
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
                    width:  ws.urgent ? 6 : (ws.exists ? 5 : 4)
                    height: width
                    radius: width / 2
                    antialiasing: true
                    visible: !ShellSettings.wsShowNumbers && !ws._showIcons
                    opacity: ws._dotFade * (ws.hovered && !ws.urgent
                             ? Math.min(1, ws._dotAlpha + 0.18)
                             : ws._dotAlpha) * ws._pulseOpacity
                    color: ws.urgent ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85)
                    scale: ws.hovered ? 1.2 : 1.0

                    Behavior on color { ColorAnimation { duration: Motion.color } }
                    Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                }

                // App icons for inactive occupied workspaces (wsShowAppIcons).
                Row {
                    anchors.centerIn: parent
                    transform: Translate { x: ws._shakeX }
                    spacing: 4
                    // Fade rather than snap when icons appear/disappear on switch.
                    visible: opacity > 0.01
                    opacity: (ws._showIcons ? 1 : 0) * ws._pulseOpacity
                    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                    Repeater {
                        // _wsApps may stay cached while icons are off. Avoid
                        // retaining image/effect delegates for invisible rows.
                        model: ws._showIcons ? ws._apps : []
                        delegate: Item {
                            required property var modelData
                            width:  root._iconSz
                            height: root._iconSz
                            scale:  ws.hovered ? 1.08 : 1.0

                            Behavior on scale {
                                enabled: !ShellSettings.reduceMotion
                                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
                            }

                            // At 100% icon opacity there's nothing to dim or tint, so
                            // skip the per-icon colorization layer and draw directly.
                            readonly property bool _fxNeeded: ShellSettings.wsIconOpacity < 0.995

                            Image {
                                id: _iconSrc
                                anchors.fill: parent
                                source: modelData.icon
                                // decode at 3× logical: DPR=2 × 1.25× compositor = 2.5×
                                // effective; 3× ensures no upscale blur on fractional
                                // displays without wasting memory on normal DPR-2 ones
                                sourceSize.width:  root._iconSz * 3
                                sourceSize.height: root._iconSz * 3
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: !parent._fxNeeded
                            }
                            // Dim washes the icon toward the accent; hover restores
                            // the true icon.
                            MultiEffect {
                                anchors.fill: _iconSrc
                                source: _iconSrc
                                visible: parent._fxNeeded
                                opacity:      ws.hovered ? 1.0 : ShellSettings.wsIconOpacity
                                colorization: ws.hovered ? 0.0 : 1.0 - ShellSettings.wsIconOpacity
                                colorizationColor: Theme.accent
                                Behavior on opacity      { NumberAnimation { duration: Motion.fast } }
                                Behavior on colorization { NumberAnimation { duration: Motion.fast } }
                            }
                            // Dot row when the same app has several windows here.
                            // Filled dots for exact count up to 3; an outline dot signals 4+.
                            Row {
                                visible: modelData.count > 1
                                anchors.right:        parent.right
                                anchors.bottom:       parent.bottom
                                anchors.rightMargin:  -2
                                anchors.bottomMargin: -2
                                spacing: 1.5
                                Repeater {
                                    model: Math.min(modelData.count, 3)
                                    Rectangle {
                                        width: 3.5; height: 3.5; radius: 1.75
                                        antialiasing: true
                                        color:        Theme.accent
                                        border.width: 0.75
                                        border.color: Theme.surface
                                    }
                                }
                                Rectangle {
                                    visible:      modelData.count > 3
                                    width: 3.5; height: 3.5; radius: 1.75
                                    antialiasing: true
                                    color:        "transparent"
                                    border.width: 0.75
                                    border.color: Theme.accent
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
