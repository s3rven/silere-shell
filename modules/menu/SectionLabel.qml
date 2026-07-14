import QtQuick
import "../../config"

// carries its own spacing so callers skip spacer Items
Item {
    id: root

    property string label: ""
    // set on the topmost heading of a page: tightens the gap under the page header. not derived from layout —
    // a heading nested in a Loader/collapsible still has nothing before it in its own column while sitting mid-page
    property bool   first: false
    property bool   showRule: true
    // a heading is not a row: it neither takes a seam nor induces one, so a group that collapses a
    // label together with its card draws no stray line across the gap
    readonly property bool suppressDividerAbove: true

    readonly property int _topGap: first ? 2 : Theme.gapSection
    readonly property int _botGap: 6

    width: parent ? parent.width : 0
    // 4px grid so cards below stay on whole physical px under fractional scaling; rounding slack falls into the gap above
    implicitHeight: 4 * Math.ceil((_topGap + _text.implicitHeight + _botGap) / 4)
    height: implicitHeight

    Rectangle {
        id: _tick
        anchors.left:           parent.left
        anchors.leftMargin:     2
        anchors.verticalCenter: _text.verticalCenter
        width:  3
        height: Math.round(_text.implicitHeight * 0.82)
        radius: 1.5
        antialiasing: true
        color:  Theme.withAlpha(Theme.menuTextMuted, 0.66)
    }

    Text {
        id: _text
        anchors.left:         _tick.right
        anchors.leftMargin:   7
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: root._botGap
        text:        root.label
        color:       Theme.withAlpha(Theme.menuTextMuted, 0.82)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 3
        font.letterSpacing:  0.4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        renderType:  Text.NativeRendering
    }

    Rectangle {
        visible:              root.showRule
        anchors.left:           _text.right
        anchors.leftMargin:     10
        anchors.right:          parent.right
        anchors.verticalCenter: _text.verticalCenter
        height: 1
        color:  Theme.menuDivider
    }
}
