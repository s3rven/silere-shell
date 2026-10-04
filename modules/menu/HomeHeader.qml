import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property string weekday: DateTime.cachedWeekday
    property string dateText: DateTime.cachedMonthDay
        + (DateTime.cachedWeek.length > 0 ? " · Week " + DateTime.cachedWeek : "")
    property string uptimeText: SysInfo.uptimeSecs > 0 ? "up " + SysInfo.uptimeLabel : ""

    readonly property bool _stackMeta: root.uptimeText.length > 0
        && _date.implicitWidth + 12 + _uptime.implicitWidth > root.width

    implicitHeight: Metrics.snap4Up(_day.implicitHeight + 2 + _date.implicitHeight
        + (root._stackMeta ? 2 + _uptime.implicitHeight : 0))
    height: implicitHeight

    ShellText {
        id: _day
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        text: root.weekday
        color: Theme.text
        font.pixelSize: Settings.fontSize + 5
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    ShellText {
        id: _date
        anchors.left: parent.left
        anchors.right: _uptime.visible && !root._stackMeta ? _uptime.left : parent.right
        anchors.rightMargin: _uptime.visible && !root._stackMeta ? 12 : 0
        anchors.top: _day.bottom
        anchors.topMargin: 2
        text: root.dateText
        color: Theme.withAlpha(Theme.subtext, 0.78)
        font.pixelSize: Settings.fontLabel
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    ShellText {
        id: _uptime
        anchors.left: root._stackMeta ? parent.left : undefined
        anchors.right: parent.right
        y: root._stackMeta ? _date.y + _date.height + 2
            : _date.y + Math.round((_date.height - height) / 2)
        visible: root.uptimeText.length > 0
        text: root.uptimeText
        color: Theme.withAlpha(Theme.subtext, 0.82)
        font.pixelSize: Settings.fontLabel
        font.weight: Font.Medium
        elide: Text.ElideRight
    }
}
