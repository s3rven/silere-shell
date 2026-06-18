import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Row {
    id: root
    spacing: 0

    property var screen: null   // ShellScreen this bar sits on, for menu placement

    // Match the Pill widgets' hover language: lean toward the accent so the
    // clock acknowledges the pointer (it's clickable — calendar / menu / cycle).
    readonly property bool  _hov:    _hover.hovered
    readonly property color _cSub:   _hov ? Theme.mix(Theme.subtext, Theme.accent, 0.30) : Theme.subtext
    readonly property color _cText:  _hov ? Theme.mix(Theme.text,    Theme.accent, 0.30) : Theme.text
    readonly property color _cFaint: _hov ? Theme.mix(Theme.withAlpha(Theme.text, 0.65), Theme.accent, 0.30)
                                          : Theme.withAlpha(Theme.text, 0.65)

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }

    scale: _calTap.pressed ? 0.95 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 18; damping: 0.5; epsilon: 0.005 } }

    Item {
        id: _dateSectionClip
        anchors.verticalCenter: parent.verticalCenter
        height:  _dateRow.implicitHeight
        width:   ShellSettings.clockShowDate ? _dateRow.implicitWidth + 8 : 0
        opacity: ShellSettings.clockShowDate ? 1.0 : 0.0
        visible: ShellSettings.clockShowDate || opacity > 0.001
        clip:    true

        Behavior on width   { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

        Row {
            id: _dateRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            CollapsingText {
                text:     DateTime.cachedDayName
                color:    root._cSub
                expanded: !ShellSettings.compactDate && !ShellSettings.barCompact
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
            text:  DateTime.cachedTime
            color: root._cText
        }
        CollapsingText {
            text:     DateTime.cachedSeconds
            color:    root._cFaint
            expanded: ShellSettings.showSeconds
            reserveText: ":00"   // constant box; ticking digits can't shift the bar
        }
        CollapsingText {
            text:     DateTime.cachedAmPm ? " " + DateTime.cachedAmPm : ""
            color:    root._cFaint
            expanded: ShellSettings.clock12h
        }
    }

    // Left-click opens the calendar; middle-click cycles date/seconds visibility;
    // right-click opens the menu. (Date/seconds also live in Settings → Clock.)
    TapHandler {
        id: _calTap
        acceptedButtons: Qt.LeftButton
        onTapped: CalendarState.toggleAt(root.mapToItem(null, root.width / 2, 0).x, root.screen)
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

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: MenuState.toggleAt(root.mapToItem(null, root.width / 2, 0).x, root.screen)
    }
}
