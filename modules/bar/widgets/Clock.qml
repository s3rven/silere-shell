import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Row {
    id: root
    spacing: 0
    leftPadding: Metrics.pillPadFor(compact)
    rightPadding: Metrics.pillPadFor(compact)

    property var screen: null
    property bool compact: ShellSettings.barCompact

    readonly property bool mirrored: ShellSettings.barWidgetOrderLeftKeys.indexOf("clock") !== -1
    layoutDirection: mirrored ? Qt.RightToLeft : Qt.LeftToRight

    readonly property bool show: ShellSettings.barShowClock
    visible: show

    readonly property bool  _hov:    (_hover.hovered && ShellSettings.barHoverHighlight) || activeFocus
    readonly property color _cSub:   _hov ? Theme.mix(Theme.subtext, Theme.accent, 0.30) : Theme.subtext
    readonly property color _cText:  _hov ? Theme.mix(Theme.text,    Theme.accent, 0.30) : Theme.text
    readonly property color _cFaint: _hov ? Theme.mix(Theme.withAlpha(Theme.text, 0.65), Theme.accent, 0.30)
                                          : Theme.withAlpha(Theme.text, 0.65)
    readonly property color _cSec:   _hov ? Theme.mix(Theme.accent, Theme.text, 0.22)
                                          : Theme.withAlpha(Theme.accent, 0.82)

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Clock, " + DateTime.cachedHour + ":" + DateTime.cachedMinute
        + DateTime.cachedSeconds + (DateTime.cachedAmPm ? " " + DateTime.cachedAmPm : "")
        + (ShellSettings.clockShowDate ? ", " + DateTime.cachedLongDate : "")
    Accessible.description: "Activate to open calendar. Middle-click cycles seconds and date."
    Accessible.onPressAction: root._openCalendar()
    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._openCalendar(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._openCalendar(); event.accepted = true }
    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._openCalendar(); event.accepted = true }

    function _openCalendar(): void {
        CalendarState.toggleAt(root.mapToItem(null, root.width / 2, 0).x, root.screen)
    }

    scale: _calTap.pressed ? 0.95 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    Item {
        id: _dateSectionClip
        anchors.verticalCenter: parent.verticalCenter
        height:  _dateRow.implicitHeight
        width:   ShellSettings.clockShowDate ? _dateRow.implicitWidth + Metrics.clockDateGapFor(root.compact) : 0
        opacity: ShellSettings.clockShowDate ? 1.0 : 0.0
        visible: ShellSettings.clockShowDate || opacity > 0.001
        clip:    true

        Behavior on width   { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

        Row {
            id: _dateRow
            anchors.verticalCenter: parent.verticalCenter
            x: root.mirrored ? parent.width - width : 0
            spacing: 0

            CollapsingText {
                text:     DateTime.cachedDayName
                color:    root._cSub
                expanded: !ShellSettings.compactDate && !root.compact
            }
            RollingText {
                text:  DateTime.cachedDateCore
                color: root._cSub
            }
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RollingText {
            text:  DateTime.cachedHour
            color: root._cText
        }
        RollingText { text: ":"; color: root._cText }
        RollingText {
            text:  DateTime.cachedMinute
            color: root._cText
        }
        CollapsingText {
            text:     DateTime.cachedSeconds
            color:    root._cSec
            expanded: ShellSettings.showSeconds
            reserveText: ":00"
        }
        CollapsingText {
            text:     DateTime.cachedAmPm ? " " + DateTime.cachedAmPm : ""
            color:    root._cFaint
            expanded: ShellSettings.clock12h
        }
    }

    TapHandler {
        id: _calTap
        acceptedButtons: Qt.LeftButton
        onTapped: root._openCalendar()
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            const s = ShellSettings.showSeconds
            const d = ShellSettings.clockShowDate
            if (!s && !d)     { ShellSettings.showSeconds = true }
            else if (s && !d) { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = true }
            else if (!s && d) { ShellSettings.showSeconds = true }
            else              { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = false }
        }
    }
}
