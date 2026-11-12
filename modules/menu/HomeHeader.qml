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
    // the switch before Weather is read: off, the service and its lookups are never created
    property string weatherText: ShellSettings.weatherEnabled && Weather.hasData && !Weather.failed
        ? Weather.glyph + " " + Weather.temperature + "°" : ""

    // asked the way the calendar asks, as Home opens; the 30-minute cache answers most
    readonly property bool _askWeather: ShellSettings.weatherEnabled && MenuState.homeActive
    on_AskWeatherChanged: if (root._askWeather) Weather.request(false)
    Component.onCompleted: if (root._askWeather) Weather.request(false)

    readonly property bool _stackMeta: root.uptimeText.length > 0
        && _date.implicitWidth + 12 + _uptime.implicitWidth > root.width

    implicitHeight: Metrics.snap4Up(_day.implicitHeight + 2 + _date.implicitHeight
        + (root._stackMeta ? 2 + _uptime.implicitHeight : 0))
    height: implicitHeight

    ShellText {
        id: _day
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: _weather.visible ? _weather.left : parent.right
        anchors.rightMargin: _weather.visible ? 12 : 0
        text: root.weekday
        color: Theme.text
        font.pixelSize: Settings.fontSize + 5
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    ShellText {
        id: _weather
        anchors.right: parent.right
        y: _day.y + Math.round((_day.height - height) / 2)
        // the day is the header's subject: a reading with no room beside it gives way
        visible: root.weatherText.length > 0
            && _day.implicitWidth + 12 + implicitWidth <= root.width
        text: root.weatherText
        // the glyph is a private-use character, which a screen reader reads as noise
        Accessible.name: visible ? "Weather " + Weather.temperature + Weather.unit + ", " + Weather.condition : ""
        color: Theme.withAlpha(Theme.text, 0.86)
        font.pixelSize: Settings.fontSize + 1
        font.weight: Font.Medium
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
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }

    ShellText {
        id: _uptime
        anchors.right: parent.right
        // a width, not a left anchor: a dropped anchor leaves the width it set, so unstacking kept the full line
        width: root._stackMeta ? parent.width : implicitWidth
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
