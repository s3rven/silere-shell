import QtQuick
import Quickshell
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
    property string accessibleName: ""
    property string accessibleValueText: String(root.value)

    property Gradient trackGradient: null

    readonly property real value: root.wraps
        ? Math.round(_wrapped(position) * displayScale) % displayScale
        : Math.round(_clamped(position) * displayScale)
    readonly property real stepSize: 1
    readonly property real minimumValue: 0
    readonly property real maximumValue: root.wraps ? root.displayScale - 1 : root.displayScale
    readonly property bool dragging: _mouse.pressed
    property real _hoveredSince: 0

    signal picked(real position)

    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleValueText
    Accessible.focusable: root.enabled && root.interactive
    Accessible.onIncreaseAction: root._nudge(1, 1)
    Accessible.onDecreaseAction: root._nudge(-1, 1)

    width: parent ? parent.width : 0
    implicitHeight: 20
    height: implicitHeight
    // rail and handle on whole device pixels, like SliderTrack
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _thumbCenter: _track.x + root._clamped(root.position) * _track.width
    property real _grab: 0
    transform: PixelSnap { item: root; dpr: root._dpr }
    opacity: root.enabled && root.interactive ? 1.0 : Theme.disabledOpacity

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
        id: _track
        x: Metrics.devicePx(_thumb.width / 2, root._dpr)
        y: Metrics.devicePx((parent.height - height) / 2, root._dpr)
        width: Math.max(1, Metrics.devicePx(parent.width, root._dpr) - 2 * x)
        height: Metrics.devicePx(6, root._dpr)
        radius: 3
        antialiasing: true
        gradient: root.trackGradient

        // the grey end of the intensity rail would otherwise dissolve into the card
        OutlineBorder {
            radius: _track.radius
            outlineWidth: 1
            outlineColor: Theme.controlTrackLine(Theme.accent, false,
                _mouse.containsMouse, _mouse.pressed)
            ColorFade on outlineColor {}
        }
    }

    SliderHandle {
        id: _thumb
        width: Metrics.devicePx(16, root._dpr)
        height: width
        y: Metrics.devicePx((parent.height - height) / 2, root._dpr)
        x: Metrics.devicePx(root._thumbCenter - width / 2, root._dpr)
        fillColor: root.thumbColor
        // the fill is the colour beneath it, so only a solid ring separates the handle from the rail
        outlineWidth: 2
        outlineColor: Theme.withAlpha(Theme.text,
            ShellSettings.highContrast || _mouse.containsMouse || _mouse.pressed ? 0.95 : 0.8)
        hovered: _mouse.containsMouse
        pressed: _mouse.pressed

        MotionBehavior on x { gate: !_mouse.pressed; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
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
        onContainsMouseChanged: if (containsMouse) root._hoveredSince = Date.now()
        onWheel: (wheel) => {
            if (Scroll.wheelBelongsToPage(containsMouse ? root._hoveredSince : Date.now())) {
                wheel.accepted = false; return
            }
            const n = Scroll.processLevelWheel(wheel, root.wheelKey)
            if (n !== 0) root._nudge(n, 1)
        }

        function _set(mx: real): void {
            root.picked(root._clamped(
                (mx - _track.x) / Math.max(1, _track.width)))
        }

        onPressed: mouse => {
            const off = mouse.x - root._thumbCenter
            root._grab = Math.abs(off) <= _thumb.width / 2 + 2 ? off : 0
            _set(mouse.x - root._grab)
        }
        onPositionChanged: mouse => { if (pressed) _set(mouse.x - root._grab) }
    }
}
