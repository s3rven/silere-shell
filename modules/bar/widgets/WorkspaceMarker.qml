pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"

// no render layer: an FBO fringes the small sprite when scaled, and 12px keeps the gem on whole pixels
Item {
    id: root

    required property string style
    required property real rowHeight
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

    readonly property real centerX: x + width / 2
    readonly property real trailX: _trailX + width / 2
    readonly property color tint: root.urgent ? Theme.warning : Theme.accent

    function pulse(): void {
        if (ShellSettings.reduceMotion) return
        _tapPulse.restart()
        glint()
    }
    function glint(): void {
        if (!root.gem || ShellSettings.reduceMotion) return
        _glintAnim.restart()
    }

    width: _dot ? 8 : 12
    height: width
    y: (rowHeight - height) / 2
    opacity: shown ? 0.92 : 0
    visible: opacity > 0.01

    x: targetX

    property real _hoverScale: root.hovered ? 1.10 : 1.0
    property real _tapScale:     1.0
    property real _moveScale:    1.0
    property real _specialScale: 1.0
    property real _glint:        -1.15
    property real _trailX:       targetX
    property real _menuOn: root.menuTargets && MenuState.open ? 1 : 0
    MotionBehavior on _menuOn {NumberAnimation { duration: Motion.ms(220); easing.type: Easing.OutCubic } }

    property real _specialOn: root.inSpecial ? 0.65 : 0
    MotionBehavior on _specialOn {NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }
    readonly property real _energy: Math.max(root._menuOn * 0.82,
                                              _specialOn,
                                              (_hoverScale - 1.0) * 4.2,
                                              (_tapScale   - 1.0) * 2.2,
                                              (_moveScale  - 1.0) * 3.0)

    scale: _hoverScale * _tapScale * _moveScale * _specialScale
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
        color: Theme.withAlpha(root.tint, 0.20)
        opacity: root.inSpecial ? 0.62 : 0.0
        scale:   root.inSpecial ? 1.0 : 0.76
        transformOrigin: Item.Center
        visible: root.gem && opacity > 0.01
        MotionBehavior on opacity {NumberAnimation { duration: Motion.ms(root.inSpecial ? 180 : 130); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(root.inSpecial ? 210 : 130); easing.type: Easing.OutQuart } }
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
        visible: opacity > 0.01
        MotionBehavior on opacity {NumberAnimation { duration: Motion.ms(root.inSpecial ? 165 : 120); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(root.inSpecial ? 190 : 120); easing.type: Easing.OutQuart } }
    }

    // filled rim, not a stroke (crisp on fractional displays); dot/ring reuse it as an energy-only halo
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width + 4
        height: width
        radius: root.gem ? 3 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Theme.withAlpha(root.tint, root.menuTargets && MenuState.open ? 0.50 : 0.30)
        opacity: root.gem ? 0.55 + root._energy * 0.22 : root._energy * 0.60
        scale: 1.0 + root._energy * (root.gem ? 0.035 : 0.10)
        visible: opacity > 0.01
        MotionBehavior on color   {ColorAnimation { duration: Motion.ms(150) } }
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
        visible: root.gem
    }

    Rectangle {
        anchors.fill: parent
        radius: root.gem ? 2 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: root.tint
        MotionBehavior on color {ColorAnimation { duration: Motion.ms(150) } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            antialiasing: true
            visible: root.gem
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.20) }
            }
        }

        Item {
            anchors.fill: parent
            clip: true
            visible: _glintAnim.running && root.gem
            Rectangle {
                width: 2
                height: parent.height + 8
                radius: 1
                antialiasing: true
                x: {
                    const t = (root._glint + 1.15) / 2.3
                    const p = root._glintDir >= 0 ? t : 1 - t
                    return Math.round(p * (parent.width + width)) - width
                }
                y: -4
                rotation: -18
                color: Qt.rgba(1, 1, 1, 0.48)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.gem ? 2 : width / 2
        rotation: root.gem ? 45 : 0
        antialiasing: true
        color: Qt.rgba(1, 1, 1, 1)
        opacity: root._menuOn * 0.22
        visible: opacity > 0.01
    }

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
        MotionBehavior on opacity {NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }
        MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(150); easing.type: Easing.OutCubic } }
    }

    SequentialAnimation {
        id: _specialPulse
        NumberAnimation { target: root; property: "_specialScale"; to: 1.055; duration: Motion.ms(90);  easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "_specialScale"; to: 1.0;   duration: Motion.ms(185); easing.type: Easing.OutQuart }
    }
    property int _glintDir: 1
    SequentialAnimation {
        id: _glintAnim
        ScriptAction { script: {
            root._glintDir = (root.targetX >= root.x) ? 1 : -1
            root._glint = -1.15
        } }
        NumberAnimation { target: root; property: "_glint"; to: 1.15; duration: Motion.ms(260); easing.type: Easing.OutCubic }
        ScriptAction { script: root._glint = -1.15 }
    }

    onInSpecialChanged: {
        if (!root.inSpecial || ShellSettings.reduceMotion) return
        _specialPulse.restart()
        root.glint()
    }

    MotionBehavior on x           { gate: root.shiftEnabled; NumberAnimation { duration: Motion.ms(190); easing.type: Easing.OutQuart } }
    MotionBehavior on opacity     {NumberAnimation { duration: Motion.ms(150) } }
    MotionBehavior on _hoverScale {NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
    MotionBehavior on _trailX     { gate: root.shiftEnabled; NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutQuart } }

    onTargetXChanged: {
        if (!root.monitorReady || root.paging) return
        if (Math.abs(targetX - x) < 2) return
        if (!root.shiftEnabled || ShellSettings.reduceMotion) return
        _moveAnim.restart()
        root.glint()
    }

    SequentialAnimation {
        id: _moveAnim
        NumberAnimation { target: root; property: "_moveScale"; to: 1.08; duration: Motion.ms(65);  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "_moveScale"; to: 1.0;  duration: Motion.ms(140); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _tapPulse
        NumberAnimation { target: root; property: "_tapScale"; to: 1.14; duration: Motion.ms(70);  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "_tapScale"; to: 1.0;  duration: Motion.ms(145); easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: _menuRippleAnim
        NumberAnimation { target: _menuRipple; property: "scale";   from: 0.9;  to: 2.7; duration: Motion.ms(540); easing.type: Easing.OutCubic }
        NumberAnimation { target: _menuRipple; property: "opacity"; from: 0.55; to: 0;   duration: Motion.ms(540); easing.type: Easing.OutCubic }
    }
    Connections {
        target: MenuState
        enabled: !ShellSettings.reduceMotion && root.barActive
        function onOpenChanged() {
            if (MenuState.open && root.menuTargets)
                _menuRippleAnim.restart()
        }
    }
}
