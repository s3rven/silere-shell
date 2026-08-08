import QtQuick
import "../../../config"
import "../../common"

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

    Accessible.role: Accessible.Heading
    Accessible.name: root.label

    Item {
        id: _band
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root._botGap
        height: root._contentH

        ShellText {
            id: _text
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            elide: Text.ElideRight
            color: Theme.withAlpha(
                Theme.mix(Theme.menuTextMuted, Theme.accent, 0.10), 0.84)
            font.pixelSize: Settings.fontCaption
            font.letterSpacing: 0.65
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            Accessible.ignored: true
        }
    }
}
