import QtQuick
import "../../config"

// carries its own spacing so callers skip spacer Items
Item {
    id: root

    property string label: ""
    property string glyph: ""
    // a page's topmost heading; not derived — one nested in a Loader still has nothing above it in its own column
    property bool   first: false
    property bool   showRule: false
    // a heading takes no seam and induces none, so collapsing it with its card draws no stray line
    readonly property bool suppressDividerAbove: true

    readonly property int _topGap: first ? 4 : Theme.gapSection
    readonly property int _botGap: 8
    readonly property int _contentH: glyph.length > 0 ? 22 : Math.max(14, _text.implicitHeight)

    width: parent ? parent.width : 0
    // 4px grid so cards below stay on whole physical px under fractional scaling; rounding slack falls into the gap above
    implicitHeight: 4 * Math.ceil((_topGap + _contentH + _botGap) / 4)
    height: implicitHeight

    Item {
        id: _band
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root._botGap
        height: root._contentH

        Rectangle {
            id: _marker
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: root.glyph.length > 0 ? 22 : 3
            height: root.glyph.length > 0 ? 22 : Math.round(_text.implicitHeight * 0.82)
            radius: root.glyph.length > 0 ? 7 : 1.5
            antialiasing: true
            color: root.glyph.length > 0
                ? Theme.withAlpha(Theme.accent, 0.075)
                : Theme.withAlpha(Theme.accent, 0.62)
            border.width: root.glyph.length > 0 ? 1 : 0
            border.color: Theme.withAlpha(Theme.accent, 0.16)

            Text {
                anchors.centerIn: parent
                visible: root.glyph.length > 0
                text: root.glyph
                color: Theme.withAlpha(Theme.accent, 0.82)
                font.family: Settings.font
                font.pixelSize: Math.max(9, Settings.fontSize - 1)
                renderType: Text.NativeRendering
            }
        }

        Text {
            id: _text
            anchors.left: _marker.right
            anchors.leftMargin: root.glyph.length > 0 ? 8 : 7
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(1, parent.width - x
                - (root.showRule ? 20 : 0)))
            text: root.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.glyph.length > 0
                ? Theme.withAlpha(Theme.mix(Theme.menuTextMuted, Theme.accent, 0.18), 0.90)
                : Theme.withAlpha(Theme.menuTextMuted, 0.82)
            font.family: Settings.font
            font.pixelSize: root.glyph.length > 0
                ? Math.max(9, Settings.fontSize - 2) : Settings.fontSize - 2
            font.letterSpacing: 0.45
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            renderType: Text.NativeRendering
        }

        Rectangle {
            visible: root.showRule
            anchors.left: _text.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: root.glyph.length > 0
                        ? Theme.withAlpha(Theme.accent, 0.20) : Theme.menuDivider
                }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
