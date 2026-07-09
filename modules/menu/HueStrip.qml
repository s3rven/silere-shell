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
    height: 12
    opacity: root.enabled && root.interactive ? (root.dimmed ? 0.4 : 1.0) : 0.45

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
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.withAlpha(Theme.accent, 0.55)
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
    }

    Rectangle {
        id: _thumb
        width: 16
        height: 16
        radius: 8
        antialiasing: true
        y: (parent.height - height) / 2
        x: Math.round(root._clampedHue(root.hue) * Math.max(0, root.width - width))
        color: root.thumbColor
        border.width: 2
        border.color: Theme.text
        scale: _mouse.pressed ? 1.18 : (_mouse.containsMouse || root.activeFocus ? 1.08 : 1.0)
        transformOrigin: Item.Center

        Behavior on x { enabled: !_mouse.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: _mouse
        enabled: root.enabled && root.interactive
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        hoverEnabled: true

        function _set(mx: real): void {
            const span = Math.max(1, width - _thumb.width)
            root.picked(root._clampedHue((mx - _thumb.width / 2) / span))
        }

        onPressed: mouse => _set(mouse.x)
        onPositionChanged: mouse => { if (pressed) _set(mouse.x) }
    }
}
