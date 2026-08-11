import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property real position: 0
    property color thumbColor: Theme.accent
    property bool interactive: true
    property bool dimmed: false
    property string accessibleName: "Hue"
    property string accessibleDescription: ""
    property string valueUnit: "degrees"
    property real displayScale: 360
    // hue is a circle, saturation is not: one wraps past the end, the other stops
    property bool wraps: true
    property string wheelKey: "accent-hue"

    property Gradient trackGradient: null

    readonly property real value: root.wraps
        ? Math.round(_wrapped(position) * displayScale) % displayScale
        : Math.round(_clamped(position) * displayScale)
    // Names consumed by Qt's QAccessibleValueInterface.
    readonly property real minimumValue: 0
    readonly property real maximumValue: root.wraps ? displayScale - 1 : displayScale
    readonly property real stepSize: 1

    FocusVisual { id: _focusVisual; target: root }

    signal picked(real position)

    width: parent ? parent.width : 0
    implicitHeight: Metrics.rowHeightFor(24)
    height: implicitHeight
    opacity: root.enabled && root.interactive ? (root.dimmed ? 0.72 : 1.0) : 0.45

    activeFocusOnTab: root.enabled && root.interactive
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: (root.accessibleDescription.length > 0
        ? root.accessibleDescription + ". " : "")
        + root.value + " " + root.valueUnit
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onIncreaseAction: if (root.enabled && root.interactive) root._nudge(1, 1)
    Accessible.onDecreaseAction: if (root.enabled && root.interactive) root._nudge(-1, 1)

    function _wrapped(p: real): real {
        return ((p % 1) + 1) % 1
    }
    function _clamped(p: real): real {
        const top = root.wraps ? (root.displayScale - 1) / root.displayScale : 1
        return Math.max(0, Math.min(top, p))
    }
    function _nudge(dir: int, mult: int): void {
        if (!root.enabled || !root.interactive) return
        const next = root.position + dir * root.stepSize * mult / root.displayScale
        root.picked(root.wraps ? root._wrapped(next) : root._clamped(next))
    }

    Keys.onLeftPressed: event => { _focusVisual.noteKeyboardInput(); root._nudge(-1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }
    Keys.onRightPressed: event => { _focusVisual.noteKeyboardInput(); root._nudge(1, (event.modifiers & Qt.ShiftModifier) ? 5 : 1); event.accepted = true }
    Keys.onPressed: _focusVisual.noteKeyboardInput()

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    Rectangle {
        id: _well
        anchors.fill: parent
        radius: Theme.radiusInline
        antialiasing: true
        color: _mouse.containsMouse || _focusVisual.active
            ? Theme.mix(Theme.menuControl, Theme.accent, 0.055)
            : Theme.menuControl
        ColorFade on color {}

        OutlineBorder {
            radius: _well.radius
            outlineWidth: _focusVisual.active ? 2 : 1
            outlineColor: _focusVisual.active
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
        gradient: root.trackGradient
    }

    Item {
        id: _thumb
        width: 18
        height: 18
        y: (parent.height - height) / 2
        x: Math.round(_track.x + root._clamped(root.position) * _track.width
            - width / 2)
        scale: _mouse.pressed ? 0.92 : (_mouse.containsMouse || _focusVisual.active ? 1.04 : 1.0)
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
            // a drag must track the finger; only a jump from elsewhere crossfades
            ColorFade on color { gate: !_mouse.pressed }
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
            root.picked(root._clamped(
                (mx - _track.x) / Math.max(1, _track.width)))
        }

        onPressed: mouse => {
            _focusVisual.takePointerFocus()
            _set(mouse.x)
        }
        onPositionChanged: mouse => { if (pressed) _set(mouse.x) }
    }

    WheelHandler {
        enabled: root.enabled && root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, root.wheelKey)
            if (n !== 0) root._nudge(n, 1)
        }
    }
}
