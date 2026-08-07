import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

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
    readonly property real value: Math.round(_wrappedHue(hue) * 360) % 360

    signal picked(real hue)

    width: parent ? parent.width : 0
    height: Metrics.rowHeightFor(24)
    opacity: root.enabled && root.interactive ? (root.dimmed ? 0.72 : 1.0) : 0.45

    activeFocusOnTab: root.enabled && root.interactive
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: (root.accessibleDescription.length > 0
        ? root.accessibleDescription + ". " : "")
        + root.value + " degrees"
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onIncreaseAction: if (root.enabled && root.interactive) root._nudgeHue(1, 1)
    Accessible.onDecreaseAction: if (root.enabled && root.interactive) root._nudgeHue(-1, 1)

    function _wrappedHue(h: real): real {
        return ((h % 1) + 1) % 1
    }
    function _clampedHue(h: real): real {
        return Math.max(0, Math.min(359 / 360, h))
    }
    function _nudgeHue(dir: int, mult: int): void {
        root.picked(root._wrappedHue(root.hue + dir * 0.02 * mult))
    }

    Keys.onLeftPressed: event => { root._nudgeHue(-1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }
    Keys.onRightPressed: event => { root._nudgeHue(1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            root.picked(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            root.picked(359 / 360)
            event.accepted = true
        }
    }

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    Rectangle {
        id: _well
        anchors.fill: parent
        radius: Theme.radiusInline
        antialiasing: true
        color: _mouse.containsMouse || root.activeFocus
            ? Theme.mix(Theme.menuControl, Theme.accent, 0.055)
            : Theme.menuControl
        ColorFade on color {}

        OutlineBorder {
            radius: _well.radius
            outlineWidth: root.activeFocus ? 2 : 1
            outlineColor: root.activeFocus
                ? Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
                : _mouse.containsMouse ? Theme.menuControlLineHot : Theme.menuControlLine
            ColorFade on outlineColor {}
        }
    }

    Rectangle {
        id: _track
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, parent.width - 12)
        height: 8
        radius: 4
        antialiasing: true
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

    Item {
        id: _thumb
        width: 18
        height: 18
        y: (parent.height - height) / 2
        x: Math.round(_track.x + root._clampedHue(root.hue) * _track.width
            - width / 2)
        scale: _mouse.pressed ? 0.92 : (_mouse.containsMouse || root.activeFocus ? 1.04 : 1.0)
        transformOrigin: Item.Center

        MotionBehavior on x { gate: !_mouse.pressed; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

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
            root.picked(root._clampedHue(
                (mx - _track.x) / Math.max(1, _track.width)))
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
