pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool _clockNeeded: ShellSettings.barShowClock
        || ShellSettings.dndSchedule
        || MenuState.homeActive
        || CalendarState.open

    SystemClock {
        id: clock
        enabled: root._clockNeeded
        precision: ShellSettings.barShowClock && ShellSettings.showSeconds && !Idle.isIdle
            ? SystemClock.Seconds : SystemClock.Minutes
    }

    property string _lastDay:       ""
    property string _lastMinute:    ""
    property string cachedDayName:  ""
    property string cachedDateCore: ""
    property string cachedLongDate: ""
    property string cachedWeekday:  ""
    property string cachedMonthDay: ""
    property string cachedWeek:     ""
    property string cachedHour:     ""
    property string cachedMinute:   ""
    property string cachedAmPm:     ""
    property string cachedSeconds:  ""
    property int hour24: 0

    Component.onCompleted: _update()

    // relative "ago" text for surfaces that report when something last ran; the caller
    // owns its own now, so nothing here ticks for a readout that is not on screen
    function agoText(thenMs: real, nowMs: real): string {
        if (thenMs <= 0) return ""
        const secs = Math.max(0, Math.round((nowMs - thenMs) / 1000))
        if (secs < 90) return "just now"
        // floor, not round: 90 min is "1 h ago", never "2 h ago"
        if (secs < 3600) return Math.floor(secs / 60) + " min ago"
        if (secs < 86400) return Math.floor(secs / 3600) + " h ago"
        const days = Math.floor(secs / 86400)
        return days <= 1 ? "yesterday" : days + " days ago"
    }

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
            cachedSeconds = ":" + String(current.getSeconds()).padStart(2, "0")
        }
    }
}
