import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property real value: 0
    property real min:   0
    property real max:   1
    property real step:  0.05
    // qt's accessible value interface reads these exact names
    readonly property real minimumValue: root.min
    readonly property real maximumValue: root.max
    readonly property real stepSize: root.step > 0
        ? root.step : Math.max(0.01, (root.max - root.min) / 100)
    property string wheelKey: ""
    property bool wheelNeedsRest: false
    property bool commitOnRelease: false
    property bool interactive: true
    property bool showThumb: true
    property bool hoverGrow: true
    property bool animate: true
    property color trackColor: Theme.controlTrackFill(Theme.accent, false,
        _ma.containsMouse, _ma.pressed)
    property color trackOutlineColor: Theme.controlTrackLine(Theme.accent, false,
        _ma.containsMouse, _ma.pressed)
    property string accessibleName: ""
    property string accessibleValueText: ""
    property real hitPad: 10

    property real thumbWidth: 14
    property real thumbHeight: 14
    property real railHeight: 6

    // rail and handle on whole device pixels: at 1.25 a 14px handle and a 6px rail land on half pixels and fringe
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _thumbW: Metrics.devicePx(root.thumbWidth, _dpr)
    readonly property real _thumbH: Metrics.devicePx(root.thumbHeight, _dpr)
    readonly property real _railH: Metrics.devicePx(root.railHeight, _dpr)
    readonly property real _railInset: root.showThumb ? Metrics.devicePx(root._thumbW / 2, _dpr) : 0
    readonly property real _railWidth: Math.max(1, Metrics.devicePx(root.width, _dpr) - root._railInset * 2)
    readonly property real _thumbCenter: root._railInset + root._railWidth * root._ratio
    // where on the handle the press landed, so grabbing it off centre does not jump the value
    property real _grab: 0

    implicitHeight: Math.max(root._railH, root._thumbH)
    transform: PixelSnap { item: root; dpr: root._dpr }

    readonly property real shownValue: _shownValue
    readonly property bool dragging: _ma.pressed
    property real _shownValue: value
    property real _hoveredSince: 0

    signal changed(real value)

    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleValueText
    Accessible.focusable: root.enabled && root.interactive
    Accessible.onIncreaseAction: root.nudge(1, 1)
    Accessible.onDecreaseAction: root.nudge(-1, 1)

    onValueChanged: if (!_ma.pressed) _shownValue = value

    readonly property real _ratio: max > min
        ? Math.max(0, Math.min(1, (_shownValue - min) / (max - min))) : 0

    function _clamp(v: real): real {
        const number = Number(v)
        return isFinite(number) ? Math.max(min, Math.min(max, number)) : min
    }
    // 0.5 + 28 * 0.05 is 1.9000000000000001; round off the float residue or it lands in settings.json
    function _snap(v: real): real {
        if (!isFinite(v)) return v
        // the bounds stay reachable when the range ends between grid steps
        if (v <= min) return min
        if (v >= max) return max
        return step > 0 ? Math.round((min + Math.round((v - min) / step) * step) * 1e6) / 1e6 : v
    }
    function _posToVal(px: real): real {
        if (width <= 0) return min
        const ratio = Math.max(0, Math.min(1,
            (px - root._railInset) / root._railWidth))
        return _clamp(_snap(min + ratio * (max - min)))
    }
    function _setFromUser(v: real): void {
        const next = _clamp(_snap(v))
        if (Math.abs(next - _shownValue) < 0.000001) return
        _shownValue = next
        if (!(commitOnRelease && _ma.pressed)) changed(next)
    }
    function _press(px: real): void {
        const off = px - root._thumbCenter
        root._grab = root.showThumb && Math.abs(off) <= root._thumbW / 2 + 2 ? off : 0
        root._setFromUser(root._posToVal(px - root._grab))
    }
    function _drag(px: real): void {
        root._setFromUser(root._posToVal(px - root._grab))
    }
    function nudge(dir: int, mult: int): void {
        if (!root.enabled || !root.interactive) return
        _setFromUser(_shownValue + dir * root.stepSize * mult)
    }

    Rectangle {
        id: _rail
        x: root._railInset
        y: Metrics.devicePx((root.height - root._railH) / 2, root._dpr)
        width: root._railWidth
        height: root._railH
        radius: 3; antialiasing: true
        color: root.trackColor
        ColorFade on color { gate: root.animate }

        Rectangle {
            // whole device px, or the fill edge slides out from under the rounded handle x
            width: Metrics.devicePx(parent.width * root._ratio, root._dpr)
            height: parent.height
            radius: parent.radius
            antialiasing: true
            color: Theme.controlTrackFill(Theme.accent, true,
                _ma.containsMouse, _ma.pressed)
            ColorFade on color { gate: root.animate }
            MotionBehavior on width {
                gate: root.animate && !_ma.pressed
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }

        OutlineBorder {
            radius: _rail.radius
            outlineWidth: 1
            outlineColor: root.trackOutlineColor
            ColorFade on outlineColor { gate: root.animate }
        }
    }

    SliderHandle {
        visible: root.showThumb
        width: root._thumbW; height: root._thumbH
        y: Metrics.devicePx((root.height - height) / 2, root._dpr)
        x: Metrics.devicePx(root._thumbCenter - width / 2, root._dpr)
        hovered: _ma.containsMouse
        pressed: _ma.pressed
        hoverGrow: root.hoverGrow
        animate: root.animate
        fillColor: Theme.sliderKnobFill(Theme.accent,
            root.hoverGrow && _ma.containsMouse, _ma.pressed)
        MotionBehavior on x {
            gate: root.animate && !_ma.pressed
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: _ma
        enabled: root.interactive
        anchors.fill: parent
        anchors.topMargin:    -root.hitPad
        anchors.bottomMargin: -root.hitPad
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // hold the grab or the Flickable steals a quick press and snaps the value to the edge
        preventStealing: true
        onPressed: (mouse) => root._press(mouse.x)
        onPositionChanged: (mouse) => { if (pressed) root._drag(mouse.x) }
        onReleased:        if (root.commitOnRelease) root.changed(root._shownValue)
        onCanceled:        root._shownValue = root.value
        onContainsMouseChanged: if (containsMouse) root._hoveredSince = Date.now()
        onWheel: (wheel) => {
            const since = !root.wheelNeedsRest ? 0
                : containsMouse ? root._hoveredSince : Date.now()
            if (root.wheelKey === "" || Scroll.wheelBelongsToPage(since)) {
                wheel.accepted = false; return
            }
            const n = Scroll.processLevelWheel(wheel, root.wheelKey)
            if (n !== 0) root.nudge(n, 1)
        }
    }
}
