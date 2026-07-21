pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Stop even the minute wake-up when the clock is hidden and neither quiet
    // hours nor an open shell surface consumes calendar data.
    readonly property bool _clockNeeded: ShellSettings.barShowClock
        || ShellSettings.dndSchedule || MenuState.open || CalendarState.open

    SystemClock {
        id: clock
        enabled: root._clockNeeded
        // Once the idle timeout lands the display is normally off. Keep quiet
        // hours accurate without waking and repainting the bar every second.
        precision: ShellSettings.barShowClock && ShellSettings.showSeconds && !Idle.isIdle
            ? SystemClock.Seconds : SystemClock.Minutes
    }

    property string _lastDay:       ""
    property string _lastMinute:    ""
    property string cachedDayName:  ""  // "ddd " — trailing space is the separator
    property string cachedDateCore: ""  // "MMM dd"
    property string cachedLongDate: ""  // "dddd, MMMM d" — menu header
    property string cachedWeekday:  ""  // "dddd" — menu masthead, weighted line
    property string cachedMonthDay: ""  // "MMMM d" — menu masthead, quiet line
    property string cachedWeek:     ""  // ISO 8601 week number, e.g. "27"
    property string cachedHour:     ""  // "HH" or "h"
    property string cachedMinute:   ""  // "mm" — split from the hour so only the changed field rolls
    property string cachedAmPm:     ""  // "AM" / "PM" in 12h mode, "" in 24h
    property string cachedSeconds:  ""  // ":ss"
    property int hour24: 0  // 24h int for the quiet-hours check

    Component.onCompleted: _update()

    // ISO 8601 week number (Monday-start). Canonical — the calendar axis reads this too.
    function isoWeek(d): int {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)
        const w1 = new Date(t.getFullYear(), 0, 4)
        return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7)
    }

    Connections {
        target: clock
        function onDateChanged() { root._update() }
        function onEnabledChanged() { if (clock.enabled) root._update() }
    }

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._refreshMinute() }
        function onShowSecondsChanged() { root._update() }
        function onBarShowClockChanged() { root._refreshMinute() }
    }

    Connections {
        target: Idle
        function onIsIdleChanged() { root._update() }
    }

    function _refreshMinute(): void {
        root._lastMinute = ""
        root._update()
    }

    function _update(): void {
        const current = clock.date
        const minute = Qt.formatDateTime(current, "yyyyMMddHHmm")
        if (minute !== _lastMinute) {
            _lastMinute = minute
            const day = minute.slice(0, 8)
            if (day !== _lastDay) {
                _lastDay        = day
                cachedDayName   = Qt.formatDateTime(current, "ddd ")
                cachedDateCore  = Qt.formatDateTime(current, "MMM dd")
                cachedLongDate  = Qt.formatDateTime(current, "dddd, MMMM d")
                cachedWeekday   = Qt.formatDateTime(current, "dddd")
                cachedMonthDay  = Qt.formatDateTime(current, "MMMM d")
                cachedWeek      = String(isoWeek(current))
            }
            cachedMinute = Qt.formatDateTime(current, "mm")
            hour24 = current.getHours()
            if (ShellSettings.clock12h) {
                cachedHour = Qt.formatDateTime(current, "h")
                cachedAmPm = Qt.formatDateTime(current, "AP")
            } else {
                cachedHour = Qt.formatDateTime(current, "HH")
                cachedAmPm = ""
            }
        }
        if (!ShellSettings.barShowClock || !ShellSettings.showSeconds) {
            cachedSeconds = ""
        } else if (!Idle.isIdle || cachedSeconds.length === 0) {
            // Freeze the last visible value while idle instead of collapsing the
            // seconds slot; input resumes the live second tick immediately.
            cachedSeconds = ":" + String(current.getSeconds()).padStart(2, "0")
        }
    }
}
