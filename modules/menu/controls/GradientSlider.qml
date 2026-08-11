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
    function _setEndpoint(end: bool): void {
        if (!root.enabled || !root.interactive) return
        root.picked(end ? root._clamped(1) : 0)
    }
    function _handleKey(event): void {
        const shifted = (event.modifiers & Qt.ShiftModifier) ? 5 : 1
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            root._nudge(-1, shifted); event.accepted = true; return
        case Qt.Key_Right:
        case Qt.Key_Up:
            root._nudge(1, shifted); event.accepted = true; return
        case Qt.Key_Home:
            root._setEndpoint(false); event.accepted = true; return
        case Qt.Key_End:
            root._setEndpoint(true); event.accepted = true; return
        case Qt.Key_PageDown:
            root._nudge(-1, 10); event.accepted = true; return
        case Qt.Key_PageUp:
            root._nudge(1, 10); event.accepted = true; return
        }
    }

    Keys.onPressed: event => {
        _focusVisual.noteKeyboardInput()
        root._handleKey(event)
    }

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
        x: _thumb.width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, parent.width - _thumb.width)
        height: 8
        radius: 2
        antialiasing: true
        gradient: root.trackGradient
    }

    SliderHandle {
        id: _thumb
        width: 12
        height: 18
        y: (parent.height - height) / 2
        x: Math.round(_track.x + root._clamped(root.position) * _track.width
            - width / 2)
        fillColor: root.thumbColor
        // the fill is the picked hue, so an accent ring can vanish into it
        focusRingColor: Theme.withAlpha(Theme.text, 0.88)
        focused: _focusVisual.active
        hovered: _mouse.containsMouse
        pressed: _mouse.pressed

        MotionBehavior on x { gate: !_mouse.pressed; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
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
