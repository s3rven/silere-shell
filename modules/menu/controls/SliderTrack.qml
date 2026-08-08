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

    implicitHeight: 16

    readonly property real shownValue: _shownValue
    readonly property bool dragging: _ma.pressed
    property real _shownValue: value

    signal interactionStarted()
    signal changed(real value)

    onValueChanged: if (!_ma.pressed) _shownValue = value

    readonly property real _ratio: max > min
        ? Math.max(0, Math.min(1, (_shownValue - min) / (max - min))) : 0

    function _clamp(v: real): real { return Math.max(min, Math.min(max, v)) }
    function _snap(v: real): real  { return step > 0 ? min + Math.round((v - min) / step) * step : v }
    function _posToVal(px: real): real {
        if (width <= 0) return min
        const ratio = Math.max(0, Math.min(1, px / width))
        return _clamp(_snap(min + ratio * (max - min)))
    }
    function _setFromUser(v: real, snap: bool): void {
        const next = _clamp(snap === false ? v : _snap(v))
        if (Math.abs(next - _shownValue) < 0.000001) return
        _shownValue = next
        if (!(commitOnRelease && _ma.pressed)) changed(next)
    }
    function nudge(dir: int, mult: int): void {
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
        case Qt.Key_PageDown:
            nudge(-1, 10); event.accepted = true; return
        case Qt.Key_PageUp:
            nudge(1, 10); event.accepted = true; return
        case Qt.Key_Home:
            _setFromUser(min, false); event.accepted = true; return
        case Qt.Key_End:
            _setFromUser(max, false); event.accepted = true; return
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        // even heights only: the track centers in the row, so an odd height puts both edges on half physical px
        height: root.interactive && (_ma.containsMouse || _ma.pressed) ? 6 : 4
        radius: height / 2; antialiasing: true
        color: root.trackColor
        clip: true
        MotionBehavior on height {
            gate: root.animate
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

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

    Item {
        visible: root.showThumb
        width: 14; height: 14
        anchors.verticalCenter: parent.verticalCenter
        x: root.width * root._ratio - width / 2
        MotionBehavior on x {
            gate: root.animate && !_ma.pressed
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 14; height: 14; radius: 7
            antialiasing: true
            // grow via scale, not width: a re-layouted odd width lands the centre on a half-pixel and the dot visibly shifts under fractional scaling
            scale: !root.hoverGrow ? 12 / 14
                 : _ma.pressed ? 1.0
                 : (_ma.containsMouse || root.focused) ? 13 / 14 : 12 / 14
            transformOrigin: Item.Center
            color: (root.hoverGrow && _ma.pressed) || root.focused
                ? Theme.accent
                : Theme.mix(Theme.text, Theme.accent,
                            root.hoverGrow && _ma.containsMouse ? 0.30 : 0.12)
            border.width: root.focused ? 1 : 0
            border.color: Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
            MotionBehavior on scale { gate: root.animate; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            MotionBehavior on color { gate: root.animate; ColorAnimation  { duration: Motion.fast } }
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
