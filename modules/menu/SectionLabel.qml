import QtQuick
import "../../config"

Item {
    id: root

    property string label: ""
    property bool   first: false
    readonly property bool suppressDividerAbove: true

    readonly property int _topGap: first ? 4 : Theme.gapSection
    readonly property int _botGap: 8
    readonly property int _contentH: Math.max(16, _text.implicitHeight)

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

        Text {
            id: _text
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.withAlpha(
                Theme.mix(Theme.menuTextMuted, Theme.accent, 0.10), 0.84)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize - 2
            font.letterSpacing: 0.65
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            renderType: Text.NativeRendering
        }
    }
}
