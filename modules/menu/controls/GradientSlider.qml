import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property real position: 0
    property color thumbColor: Theme.accent
    property bool interactive: true
    property real displayScale: 360
    // hue is a circle, saturation is not: one wraps past the end, the other stops
    property bool wraps: true
    property string wheelKey: "accent-hue"

    property Gradient trackGradient: null

    readonly property real value: root.wraps
        ? Math.round(_wrapped(position) * displayScale) % displayScale
        : Math.round(_clamped(position) * displayScale)
    readonly property real stepSize: 1

    signal picked(real position)

    width: parent ? parent.width : 0
    implicitHeight: Metrics.rowHeightFor(24)
    height: implicitHeight
    opacity: root.enabled && root.interactive ? 1.0 : 0.45

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
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    Rectangle {
        id: _well
        anchors.fill: parent
        radius: Theme.radiusInline
        antialiasing: true
        color: _mouse.containsMouse
            ? Theme.mix(Theme.menuControl, Theme.accent, 0.055)
            : Theme.menuControl
        ColorFade on color {}

        OutlineBorder {
            radius: _well.radius
            outlineWidth: 1
            outlineColor: _mouse.containsMouse ? Theme.menuControlLineHot : Theme.menuControlLine
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
