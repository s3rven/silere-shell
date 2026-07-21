import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property real hue: 0
    property real saturation: 0.72
    property real lightness: 0.70
    property color thumbColor: Qt.hsla(root.hue, root.saturation, root.lightness, 1.0)
    property bool interactive: true
    property bool dimmed: false
    property string accessibleName: "Hue"
    property string accessibleDescription: ""

    signal picked(real hue)

    width: parent ? parent.width : 0
    height: 24
    opacity: root.enabled && root.interactive ? (root.dimmed ? 0.72 : 1.0) : 0.45

    activeFocusOnTab: root.enabled && root.interactive
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription

    function _wrappedHue(h: real): real {
        return ((h % 1) + 1) % 1
    }
    function _clampedHue(h: real): real {
        return Math.max(0, Math.min(1, h))
    }
    function _nudgeHue(dir: int, mult: int): void {
        root.picked(root._wrappedHue(root.hue + dir * 0.02 * mult))
    }

    Keys.onLeftPressed: event => { root._nudgeHue(-1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }
    Keys.onRightPressed: event => { root._nudgeHue(1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }

    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    Rectangle {
        id: _well
        anchors.fill: parent
        radius: 8
        antialiasing: true
        color: _mouse.containsMouse || root.activeFocus
            ? Theme.mix(Theme.menuControl, Theme.accent, 0.055)
            : Theme.menuControl
        border.width: 1
        border.color: root.activeFocus
            ? Theme.withAlpha(Theme.accent, 0.58)
            : _mouse.containsMouse ? Theme.menuControlLineHot : Theme.menuControlLine
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        id: _track
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, parent.width - 12)
        height: 8
        radius: 4
        antialiasing: true
        clip: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.000; color: Qt.hsla(0.000, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 0.167; color: Qt.hsla(0.167, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 0.333; color: Qt.hsla(0.333, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 0.500; color: Qt.hsla(0.500, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 0.667; color: Qt.hsla(0.667, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 0.833; color: Qt.hsla(0.833, root.saturation, root.lightness, 1.0) }
            GradientStop { position: 1.000; color: Qt.hsla(1.000, root.saturation, root.lightness, 1.0) }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.withAlpha(Theme.text, 0.24)
        }
    }

    Item {
        id: _thumb
        width: 18
        height: 18
        y: (parent.height - height) / 2
        x: Math.round(_track.x + root._clampedHue(root.hue)
            * Math.max(0, _track.width - width))
        scale: _mouse.pressed ? 0.92 : (_mouse.containsMouse || root.activeFocus ? 1.04 : 1.0)
        transformOrigin: Item.Center

        Behavior on x { enabled: !_mouse.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: 9
            antialiasing: true
            color: Theme.menuPane
            border.width: 1
            border.color: Theme.withAlpha(Theme.text, 0.52)
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 6
            antialiasing: true
            color: root.thumbColor
        }
    }

    MouseArea {
        id: _mouse
        enabled: root.enabled && root.interactive
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        hoverEnabled: true

        function _set(mx: real): void {
            const span = Math.max(1, _track.width - _thumb.width)
            root.picked(root._clampedHue(
                (mx - _track.x - _thumb.width / 2) / span))
        }

        onPressed: mouse => _set(mouse.x)
        onPositionChanged: mouse => { if (pressed) _set(mouse.x) }
    }

    WheelHandler {
        enabled: root.enabled && root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, "accent-hue")
            if (n !== 0) root._nudgeHue(n, 1)
        }
    }
}
