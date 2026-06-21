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

    signal changed(real value)

    function _clamp(v) { return Math.max(min, Math.min(max, v)) }
    function _snap(v)  { return step > 0 ? min + Math.round((v - min) / step) * step : v }
    function _posToVal(px) {
        if (_track.width <= 0) return root.min
        const ratio = Math.max(0, Math.min(1, px / _track.width))
        return _clamp(_snap(root.min + ratio * (root.max - root.min)))
    }
    function _nudge(dir) {
        root.changed(_clamp(_snap(root.value + dir * root.step)))
    }

    // 4px multiple so row.y inside SettingsCard lands on whole physical
    // px at 1.25x and every divider renders the same hairline thickness.
    width:          parent ? parent.width : 0
    height:         52
    implicitHeight: 52
    opacity: root.enabled ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.displayValue
    Keys.onLeftPressed:  root._nudge(-1)
    Keys.onDownPressed:  root._nudge(-1)
    Keys.onRightPressed: root._nudge(1)
    Keys.onUpPressed:    root._nudge(1)

    HoverHandler { id: _rowHover; enabled: root.enabled; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    // Hover background, clipped rounded rect (see RowHoverBg).
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       _rowHover.hovered || root.activeFocus
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    // ── Top line: glyph + label (left), value (right) ─────────────────────
    Item {
        id: _head
        anchors.left:       parent.left
        anchors.leftMargin: 12
        anchors.right:      _valueText.left
        anchors.rightMargin: 10
        anchors.top:        parent.top
        anchors.topMargin:  8
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
            Behavior on color { ColorAnimation { duration: Motion.slow } }
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
        color:          Theme.withAlpha(Theme.text, 0.55)
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
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
        anchors.topMargin:   7
        height: 16

        readonly property real _ratio: root.max > root.min
            ? Math.max(0, Math.min(1, (root.value - root.min) / (root.max - root.min))) : 0

        Rectangle {
            id: _trackBg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6
            radius: 3; antialiasing: true
            color: Theme.menuTrack
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 0
            // End the fill exactly at the thumb's centre. The thumb travels
            // (width − thumbW) while a full-width fill would travel `width`, so
            // tying the fill to the thumb keeps them locked instead of drifting
            // apart as you drag (which looked "warped" with a solid fill).
            width: _track._ratio <= 0 ? 0
                 : Math.max(_trackBg.radius * 2, _thumb.x + _thumb.width / 2)
            height: _trackBg.height
            radius: _trackBg.radius; antialiasing: true
            // Solid fill, not a translucent wash — a see-through accent over the dark
            // track reads as muddy/blurry; opaque keeps the bar crisp.
            color: _trackMa.pressed ? Theme.mix(Theme.accent, Theme.text, 0.22) : Theme.accent
            Behavior on width {
                enabled: !_trackMa.pressed
                NumberAnimation { duration: Motion.instant; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Rectangle {
            id: _thumb
            width: 12; height: 12; radius: 6
            antialiasing: true
            anchors.verticalCenter: parent.verticalCenter
            x: _track._ratio * (_track.width - width)
            color: _trackMa.pressed ? Theme.accent : Theme.text
            border.width: 1
            border.color: Theme.withAlpha(Theme.subtext, 0.12)
            scale: _trackMa.pressed ? 0.86 : 1.0
            transformOrigin: Item.Center

            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on x {
                enabled: !_trackMa.pressed
                NumberAnimation { duration: Motion.instant; easing.type: Easing.OutCubic }
            }

            HoverHandler { id: _thumbHover }

            Rectangle {
                anchors.centerIn: parent
                readonly property bool _on: _thumbHover.hovered || _trackMa.pressed
                width:  _on ? 20 : 16
                height: width; radius: width / 2
                antialiasing: true
                color: _trackMa.pressed ? Theme.withAlpha(Theme.accent, 0.20)
                                        : Theme.withAlpha(Theme.text, 0.06)
                opacity: _on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                Behavior on width   { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                Behavior on color   { ColorAnimation  { duration: Motion.fast } }
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
            onPressed:         (mouse) => root.changed(root._posToVal(mouse.x))
            onPositionChanged: (mouse) => { if (pressed) root.changed(root._posToVal(mouse.x)) }
            // Through the shared accumulator so touchpads step once per notch
            // instead of once per micro-event (matches the bar widgets).
            onWheel: (wheel) => {
                const n = Scroll.processControlWheel(wheel, "slider:" + root.label)
                if (n !== 0) root._nudge(n)
            }
        }
    }
}
