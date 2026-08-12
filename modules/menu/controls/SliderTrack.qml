import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    property real value: 0
    property real min:   0
    property real max:   1
    property real step:  0.05
    property string wheelKey: ""
    property bool commitOnRelease: false
    property bool focused: false
    property bool interactive: true
    property bool showThumb: true
    property bool hoverGrow: true
    property bool animate: true
    property color trackColor: Theme.menuTrack
    property real hitPad: 10

    readonly property real thumbWidth: 10
    readonly property real thumbHeight: 16
    readonly property real _railInset: root.showThumb ? root.thumbWidth / 2 : 0
    readonly property real _railWidth: Math.max(1, root.width - root._railInset * 2)

    implicitHeight: 16

    readonly property real shownValue: _shownValue
    readonly property bool dragging: _ma.pressed
    property real _shownValue: value

    signal interactionStarted()
    signal changed(real value)

    onValueChanged: if (!_ma.pressed) _shownValue = value

    readonly property real _ratio: max > min
        ? Math.max(0, Math.min(1, (_shownValue - min) / (max - min))) : 0

    function _clamp(v: real): real {
        const number = Number(v)
        return isFinite(number) ? Math.max(min, Math.min(max, number)) : min
    }
    function _snap(v: real): real  { return step > 0 ? min + Math.round((v - min) / step) * step : v }
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
    function nudge(dir: int, mult: int): void {
        if (!root.interactive) return
        const baseStep = step > 0 ? step : Math.max(0.01, (max - min) / 100)
        _setFromUser(_shownValue + dir * baseStep * mult)
    }
    function handleKey(event): void {
        if (!root.interactive) return
        const big = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            nudge(-1, big); event.accepted = true; return
        case Qt.Key_Right:
        case Qt.Key_Up:
            nudge(1, big); event.accepted = true; return
        case Qt.Key_Home:
            _setFromUser(min); event.accepted = true; return
        case Qt.Key_End:
            _setFromUser(max); event.accepted = true; return
        case Qt.Key_PageDown:
            nudge(-1, 10); event.accepted = true; return
        case Qt.Key_PageUp:
            nudge(1, 10); event.accepted = true; return
        }
    }

    Rectangle {
        x: root._railInset
        anchors.verticalCenter: parent.verticalCenter
        width: root._railWidth
        height: 4
        radius: Math.min(2, height / 2); antialiasing: true
        color: root.trackColor
        clip: true

        Rectangle {
            width: parent.width * root._ratio
            height: parent.height
            radius: parent.radius
            antialiasing: true
            // full-strength accent glares against the panel; the dark track does the damping
            color: Theme.withAlpha(Theme.accent, 0.80)
            MotionBehavior on width {
                gate: root.animate && !_ma.pressed
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }

    SliderHandle {
        visible: root.showThumb
        width: root.thumbWidth; height: root.thumbHeight
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(root._railInset + root._railWidth * root._ratio - width / 2)
        focused: root.focused
        hovered: _ma.containsMouse
        pressed: _ma.pressed
        hoverGrow: root.hoverGrow
        animate: root.animate
        fillColor: (root.hoverGrow && _ma.pressed) || root.focused
            ? Theme.accent
            : Theme.mix(Theme.text, Theme.accent,
                        root.hoverGrow && _ma.containsMouse ? 0.30 : 0.12)
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
        onPressed: (mouse) => {
            root.interactionStarted()
            root._setFromUser(root._posToVal(mouse.x))
        }
        onPositionChanged: (mouse) => { if (pressed) root._setFromUser(root._posToVal(mouse.x)) }
        onReleased:        if (root.commitOnRelease) root.changed(root._shownValue)
        onCanceled:        root._shownValue = root.value
        onWheel: (wheel) => {
            if (root.wheelKey === "") { wheel.accepted = false; return }
            const n = Scroll.processControlWheel(wheel, root.wheelKey)
            if (n !== 0) root.nudge(n, 1)
        }
    }
}
