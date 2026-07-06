pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    SystemClock {
        id: clock
        precision: ShellSettings.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    property string _lastDay:       ""
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
    }

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._update() }
        function onShowSecondsChanged() { root._update() }
    }

    function _update(): void {
        const day = Qt.formatDateTime(clock.date, "yyyyMMdd")
        if (day !== _lastDay) {
            _lastDay        = day
            cachedDayName   = Qt.formatDateTime(clock.date, "ddd ")
            cachedDateCore  = Qt.formatDateTime(clock.date, "MMM dd")
            cachedLongDate  = Qt.formatDateTime(clock.date, "dddd, MMMM d")
            cachedWeekday   = Qt.formatDateTime(clock.date, "dddd")
            cachedMonthDay  = Qt.formatDateTime(clock.date, "MMMM d")
            cachedWeek      = String(isoWeek(clock.date))
        }
        cachedMinute = Qt.formatDateTime(clock.date, "mm")
        if (ShellSettings.clock12h) {
            cachedHour = Qt.formatDateTime(clock.date, "h")
            cachedAmPm = Qt.formatDateTime(clock.date, "AP")
        } else {
            cachedHour = Qt.formatDateTime(clock.date, "HH")
            cachedAmPm = ""
        }
        cachedSeconds = ShellSettings.showSeconds
            ? Qt.formatDateTime(clock.date, ":ss")
            : ""
    }
}
