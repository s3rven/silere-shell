pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"

// no render layer: an FBO fringes the small sprite when scaled, and the even sprite sizes keep the gem on whole pixels
Item {
    id: root

    required property string style
    required property real rowHeight
    required property real cellWidth
    required property real targetX
    required property bool shown
    required property bool inSpecial
    required property bool urgent
    required property bool menuTargets
    required property bool barActive
    required property bool paging
    required property bool monitorReady
    required property bool shiftEnabled
    property bool hovered: false

    readonly property bool gem: style === "gem"
    readonly property bool _dot: style === "dot"
    readonly property bool _bar: style === "bar"
    readonly property int travelDuration: 190

    readonly property real centerX: x + width / 2
    readonly property color tint: root.urgent ? Theme.warning : Theme.accent

    function _motionAllowed(): bool {
        return root.shown && root.barActive
            && !ShellSettings.reduceMotion && !Idle.isIdle
    }
    function _settleMenuMotion(): void {
        _menuRippleAnim.stop()
        _menuRipple.opacity = 0
        _menuRipple.scale = 1
    }
    function _settleMotion(): void {
        _specialPulse.retire()
        _glintAnim.stop()
        _moveAnim.retire()
        _tapPulse.retire()
        root._settleMenuMotion()
        root._glint = -1.15
    }
    function pulse(): void {
        if (!root._motionAllowed()) return
        _tapPulse.restart()
        glint()
    }
    function glint(): void {
        if ((!root.gem && !root._bar) || !root._motionAllowed()) return
        _glintAnim.restart()
    }

    readonly property real _sprite: _dot ? 2 * Math.round(rowHeight / 6)
                                         : 2 * Math.round(rowHeight / 4)
    // settled width for the caller to centre on; feeding the animated one back into targetX restarts the slide every frame
    readonly property real markerWidth: _bar ? Math.max(14, cellWidth - 8) : _sprite
    width:  markerWidth
    height: _bar ? 3 : _sprite
    // keep the line two pixels clear of the cell edge so its halo is not clipped by the bar
    y: _bar ? rowHeight - 5 : (rowHeight - height) / 2
    opacity: shown ? (_bar ? 0.98 : 0.92) : 0
    visible: opacity > 0.01

    x: targetX

    property real _hoverScale: root.hovered ? 1.10 : 1.0
    property real _tapScale:     1.0
    property real _moveScale:    1.0
    property real _specialScale: 1.0
    property real _glint:        -1.15
    readonly property bool _menuFx: root.menuTargets && MenuState.open
        && ShellSettings.wsMenuPulse
    property real _menuOn: root._menuFx ? 1 : 0
    MotionBehavior on _menuOn {
        gate: root.shown && root.barActive
        NumberAnimation { duration: Motion.ms(220); easing.type: Easing.OutCubic }
    }

    property real _specialOn: root.inSpecial ? 0.65 : 0
    MotionBehavior on _specialOn {
        gate: root._motionAllowed()
        NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic }
    }
    readonly property real _energy: Math.max(root._menuOn * 0.82,
                                              _specialOn,
                                              (_hoverScale - 1.0) * 4.2,
                                              (_tapScale   - 1.0) * 2.2,
                                              (_moveScale  - 1.0) * 3.0)

    // the sprite bounces; the wider line gets only a restrained version of that response
    readonly property real _scaleStack: _hoverScale * _tapScale * _moveScale * _specialScale
    scale: _bar ? 1 + (_scaleStack - 1) * 0.22 : _scaleStack
    transformOrigin: Item.Center

    Rectangle {
        anchors.centerIn: parent
        width:  parent.width + 14
        height: width
        radius: 4
        rotation: 45
        antialiasing: true
        color: Theme.withAlpha(root.tint, 0.34)
        opacity: root._energy * 0.22
        scale: 0.70 + root._energy * 0.22
        visible: root.gem && opacity > 0.01
    }

    Rectangle {
        id: _menuRipple
        anchors.centerIn: parent
        width:  parent.width + 6
        height: width
        radius: root.gem ? 4 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Theme.withAlpha(root.tint, 0.5)
        opacity: 0
        scale: 1.0
        transformOrigin: Item.Center
        visible: !root._bar && opacity > 0.01
    }

    // special-workspace frame; filled layers not strokes — 1px rotated borders look uneven on fractional displays
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width + 16
        height: width
        radius: 4
        rotation: 45
        antialiasing: true
        color: Theme.withAlpha(root.tint, 0.20)
        opacity: root.inSpecial ? 0.62 : 0.0
        scale:   root.inSpecial ? 1.0 : 0.76
        transformOrigin: Item.Center
        visible: root.gem && opacity > 0.01
        MotionBehavior on opacity { gate: root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.inSpecial ? 180 : 130); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   { gate: root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.inSpecial ? 210 : 130); easing.type: Easing.OutQuart } }
    }
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width + 8
        height: width
        radius: root.gem ? 3 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Theme.withAlpha(root.tint, 0.34)
        opacity: root.inSpecial ? 0.96 : 0.0
        scale:   root.inSpecial ? 1.0 : 0.68
        transformOrigin: Item.Center
        visible: !root._bar && opacity > 0.01
        MotionBehavior on opacity { gate: root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.inSpecial ? 165 : 120); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   { gate: root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.inSpecial ? 190 : 120); easing.type: Easing.OutQuart } }
    }

    // filled rim, not a stroke (crisp on fractional displays); dot/ring reuse it as an energy-only halo
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width + 4
        height: width
        radius: root.gem ? 3 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Theme.withAlpha(root.tint, root._menuFx ? 0.50 : 0.30)
        opacity: root.gem ? 0.28 + root._energy * 0.30 : root._energy * 0.60
        scale: 1.0 + root._energy * (root.gem ? 0.035 : 0.10)
        visible: !root._bar && opacity > 0.01
        MotionBehavior on color   {ColorAnimation { duration: Motion.color } }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        width: parent.width + 4
        height: parent.height + 2
        radius: height / 2
        antialiasing: true
        color: Qt.rgba(0, 0, 0, 0.30)
        opacity: root._bar ? 0.45 : 0
        visible: root._bar
    }

    // a compact second rail distinguishes a special workspace without changing the main target
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: -3
        width:  Math.max(7, parent.width * 0.42)
        height: 2
        radius: height / 2
        antialiasing: true
        color: root.tint
        opacity: root._bar ? root._specialOn * 1.35 : 0
        visible: root._bar && opacity > 0.01
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
        opacity: 0.10
        visible: root.gem
    }

    Rectangle {
        anchors.fill: parent
        radius: root.gem ? 2 : Math.min(width, height) / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: root.tint
        MotionBehavior on color {ColorAnimation { duration: Motion.color } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            antialiasing: true
            visible: root.gem
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
            }
        }

        Item {
            anchors.fill: parent
            clip: true
            visible: _glintAnim.running && (root.gem || root._bar)
            Rectangle {
                width: root._bar ? 7 : 2
                height: parent.height + 8
                radius: 1
                antialiasing: true
                x: {
                    const t = (root._glint + 1.15) / 2.3
                    const p = root._glintDir >= 0 ? t : 1 - t
                    return Math.round(p * (parent.width + width)) - width
                }
                y: -4
                rotation: root._bar ? 0 : -18
                color: Qt.rgba(1, 1, 1, root._bar ? 0.34 : 0.48)
            }
        }

    }

    Rectangle {
        anchors.fill: parent
        radius: root.gem ? 2 : Math.min(width, height) / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Qt.rgba(1, 1, 1, 1)
        opacity: root._menuOn * 0.22
        visible: opacity > 0.01
    }

    Rectangle {
        readonly property bool _show: Notifications.silencingActive && Notifications.missedCount > 0
        // placed, not anchored: the underline needs it at the line's tip and a conditional anchor leaves the stale edge set
        x: root._bar ? root.width - width + 2 : (root.width - width) / 2
        y: -1
        width:  4
        height: 4
        radius: width / 2
        antialiasing: true
        color: Theme.error
        opacity: _show ? 1 : 0
        scale:   _show ? 1 : 0.2
        transformOrigin: Item.Center
        visible: opacity > 0.01
        MotionBehavior on opacity {NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(150); easing.type: Easing.OutCubic } }
    }

    BumpAnimation {
        id: _specialPulse
        target: root
        targetProperty: "_specialScale"
        peak: 1.055
    }
    property int _glintDir: 1
    SequentialAnimation {
        id: _glintAnim
        ScriptAction { script: {
            root._glintDir = (root.targetX >= root.x) ? 1 : -1
            root._glint = -1.15
        } }
        NumberAnimation { target: root; property: "_glint"; to: 1.15; duration: Motion.ms(root._bar ? 220 : 260); easing.type: Easing.OutCubic }
        ScriptAction { script: root._glint = -1.15 }
    }

    onInSpecialChanged: {
        if (!root.inSpecial || !root._motionAllowed()) return
        _specialPulse.restart()
        root.glint()
    }

    onShownChanged: if (!shown) root._settleMotion()
    onBarActiveChanged: if (!barActive) root._settleMotion()
    onMenuTargetsChanged: if (!menuTargets) root._settleMenuMotion()

    MotionBehavior on x           { gate: root.shiftEnabled && root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.travelDuration); easing.type: Easing.OutQuart } }
    MotionBehavior on width       { gate: root.shiftEnabled && root._bar && root._motionAllowed(); NumberAnimation { duration: Motion.ms(root.travelDuration); easing.type: Easing.OutQuart } }
    MotionBehavior on opacity     {NumberAnimation { duration: Motion.ms(150) } }
    MotionBehavior on _hoverScale { gate: root._motionAllowed(); NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }

    onTargetXChanged: {
        if (!root.monitorReady || root.paging) return
        if (Math.abs(targetX - x) < 2) return
        if (!root.shiftEnabled || !root._motionAllowed()) return
        _moveAnim.restart()
    }

    BumpAnimation {
        id: _moveAnim
        target: root
        targetProperty: "_moveScale"
        peak: 1.08
    }

    BumpAnimation {
        id: _tapPulse
        target: root
        targetProperty: "_tapScale"
        peak: 1.14
    }

    ParallelAnimation {
        id: _menuRippleAnim
        NumberAnimation { target: _menuRipple; property: "scale";   from: 0.9;  to: 2.7; duration: Motion.ms(540); easing.type: Easing.OutCubic }
        NumberAnimation { target: _menuRipple; property: "opacity"; from: 0.55; to: 0;   duration: Motion.ms(540); easing.type: Easing.OutCubic }
    }
    Connections {
        target: MenuState
        enabled: ShellSettings.wsMenuPulse && root.menuTargets
            && root._motionAllowed()
        function onOpenChanged() {
            if (!MenuState.open) return
            if (root._bar) root.glint()
            else _menuRippleAnim.restart()
        }
    }
    Connections {
        target: ShellSettings
        function onWsMenuPulseChanged() {
            if (!ShellSettings.wsMenuPulse) root._settleMenuMotion()
        }
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settleMotion()
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) root._settleMotion()
        }
    }
}
