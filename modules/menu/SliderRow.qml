import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:        ""
    property string label:        ""
    property string displayValue: {
        const range = max - min
        if (range <= 0) return "0%"
        const ratio = Math.max(0, Math.min(1, (value - min) / range))
        return Math.round(ratio * 100) + "%"
    }
    property real   value:        0.5
    property real   min:          0.0
    property real   max:          1.0
    property real   step:         0.05
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    property color  glyphColor:   Theme.withAlpha(Theme.subtext, 0.85)
    property real   _shownValue: value

    signal changed(real value)

    function _clamp(v) { return Math.max(min, Math.min(max, v)) }
    function _snap(v)  { return step > 0 ? min + Math.round((v - min) / step) * step : v }
    function _posToVal(px) {
        if (_track.width <= 0) return root.min
        const ratio = Math.max(0, Math.min(1, px / _track.width))
        return _clamp(_snap(root.min + ratio * (root.max - root.min)))
    }
    onValueChanged: if (!_trackMa.pressed) _shownValue = value

    function _setFromUser(v: real, snap: bool): void {
        const next = _clamp(snap === false ? v : _snap(v))
        if (Math.abs(next - root._shownValue) < 0.000001) return
        root._shownValue = next
        root.changed(next)
    }
    function _nudge(dir: int, mult: int): void {
        const baseStep = step > 0 ? step : Math.max(0.01, (max - min) / 100)
        root._setFromUser(root._shownValue + dir * baseStep * mult)
    }
    function _setEndpoint(toMax: bool): void {
        root._setFromUser(toMax ? root.max : root.min, false)
    }
    function _handleKey(event): void {
        const big = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            root._nudge(-1, big); event.accepted = true; return
        case Qt.Key_Right:
        case Qt.Key_Up:
            root._nudge(1, big); event.accepted = true; return
        case Qt.Key_PageDown:
            root._nudge(-1, 10); event.accepted = true; return
        case Qt.Key_PageUp:
            root._nudge(1, 10); event.accepted = true; return
        case Qt.Key_Home:
            root._setEndpoint(false); event.accepted = true; return
        case Qt.Key_End:
            root._setEndpoint(true); event.accepted = true; return
        }
    }

    // 4px multiple so row.y inside SettingsCard lands on whole physical
    // px at 1.25x and every divider renders the same hairline thickness.
    width:          parent ? parent.width : 0
    height:         56
    implicitHeight: 56
    opacity: root.enabled ? 1.0 : 0.45

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.displayValue
    Keys.onPressed: event => root._handleKey(event)

    // ── Top line: glyph + label (left), value (right) ─────────────────────
    Item {
        id: _head
        anchors.left:       parent.left
        anchors.leftMargin: 12
        anchors.right:      _valueText.left
        anchors.rightMargin: 10
        anchors.top:        parent.top
        anchors.topMargin:  9
        height: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        clip: true

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text:           root.glyph
            color:          root.glyphColor
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType:     Text.NativeRendering
        }
        Text {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     root.glyph.length > 0 ? 8 : 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
    }

    Text {
        id: _valueText
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: _head.verticalCenter
        text:           root.displayValue
        color:          Theme.withAlpha(Theme.text, 0.58)
        font.family:    Settings.font
        font.pixelSize: Math.max(9, Settings.fontSize - 1)
        font.weight:    Font.DemiBold
        renderType:     Text.NativeRendering
    }

    // ── Bottom line: full-width track ─────────────────────────────────────
    Item {
        id: _track
        anchors.left:        parent.left
        anchors.right:       parent.right
        anchors.leftMargin:  12
        anchors.rightMargin: 12
        anchors.top:         _head.bottom
        anchors.topMargin:   8
        height: 20

        readonly property real _ratio: root.max > root.min
            ? Math.max(0, Math.min(1, (root._shownValue - root.min) / (root.max - root.min))) : 0

        Rectangle {
            id: _trackBg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4
            radius: height / 2; antialiasing: true
            color: Theme.menuTrack
            clip: true

            Rectangle {
                width: parent.width * _track._ratio
                height: parent.height
                radius: parent.radius
                antialiasing: true
                color: Theme.accent
            }
        }

        Item {
            id: _thumb
            width: 14; height: 14
            anchors.verticalCenter: parent.verticalCenter
            x: _track.width * _track._ratio - width / 2

            Rectangle {
                id: _knob
                anchors.centerIn: parent
                width: 12
                height: width
                radius: width / 2
                antialiasing: true
                color: root.activeFocus ? Theme.accent : Theme.mix(Theme.text, Theme.accent, 0.12)
                border.width: root.activeFocus ? 1 : 0
                border.color: Theme.withAlpha(Theme.accent, 0.55)
            }
        }

        MouseArea {
            id: _trackMa
            enabled: root.enabled
            anchors.fill: parent
            anchors.topMargin:    -8
            anchors.bottomMargin: -8
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            // Hold the grab so a quick press inside the scrollable settings page
            // can't be stolen by the Flickable and snap the value to the edge.
            preventStealing: true
            onPressed:         (mouse) => root._setFromUser(root._posToVal(mouse.x))
            onPositionChanged: (mouse) => { if (pressed) root._setFromUser(root._posToVal(mouse.x)) }
            onCanceled:        root._shownValue = root.value
            // Through the shared accumulator so touchpads step once per notch
            // instead of once per micro-event (matches the bar widgets).
            onWheel: (wheel) => {
                const n = Scroll.processControlWheel(wheel, "slider:" + root.label)
                if (n !== 0) root._nudge(n, 1)
            }
        }
    }
}
