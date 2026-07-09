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
    Keys.onPressed: event => _track.handleKey(event)

    HoverHandler { id: _rowHover; enabled: root.enabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       (_rowHover.hovered || root.activeFocus) && root.enabled
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    // ── Top line: glyph + label (left), value (right) ─────────────────────
    Item {
        id: _head
        anchors.left:       parent.left
        anchors.leftMargin: 14
        anchors.right:      _valueText.left
        anchors.rightMargin: 10
        anchors.top:        parent.top
        anchors.topMargin:  8
        // fixed head height so the track's position can't drift with the font's line height
        height: 20
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
            font.pixelSize: Settings.iconSize + 2
            renderType:     Text.NativeRendering
        }
        Text {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     root.glyph.length > 0 ? 10 : 0
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
    // bottom-anchored (not chained under the head) so the thumb keeps clear of the card edge at every font
    SliderTrack {
        id: _track
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.leftMargin:   14
        anchors.rightMargin:  12
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: 4
        height: 20
        hitPad: 8

        interactive: root.enabled
        focused:     root.activeFocus
        value: root.value
        min:   root.min
        max:   root.max
        step:  root.step
        wheelKey: "slider:" + root.label
        onChanged: value => root.changed(value)
    }
}
