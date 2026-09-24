pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    function clockNeeded(barClock: bool, overview: bool, dndSchedule: bool,
            homeActive: bool, calendarOpen: bool): bool {
        return (barClock && !overview) || dndSchedule || homeActive || calendarOpen
    }

    readonly property bool _clockNeeded: root.clockNeeded(
        ShellSettings.barShowClock, OverviewState.active,
        ShellSettings.dndSchedule, MenuState.homeActive, CalendarState.open)

    // a monotonic timer stops across suspend, so the next tick can land up to a minute after wake
    property bool _resync: false

    SystemClock {
        id: clock
        enabled: root._clockNeeded && !root._resync
        precision: ShellSettings.barShowClock && ShellSettings.showSeconds
            && !Idle.isIdle && !OverviewState.active
            ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property date currentDate: clock.date

    property string _lastDay:       ""
    property string _lastMinute:    ""
    property string cachedDayName:  ""
    property string cachedDateCore: ""
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

    // qt only counts 12-hour when AP shares the format string; "h" alone still reads 0-23
    function clockHour(d): string {
        if (!ShellSettings.clock12h) return Qt.formatDateTime(d, "HH")
        const text = Qt.formatDateTime(d, "h'|'AP")
        const at = text.indexOf("|")
        return at < 0 ? text : text.slice(0, at)
    }

    function clockSuffix(d): string {
        return ShellSettings.clock12h ? Qt.formatDateTime(d, "AP") : ""
    }

    function clockText(d): string {
        const suffix = root.clockSuffix(d)
        return root.clockHour(d) + ":" + Qt.formatDateTime(d, "mm")
            + (suffix.length > 0 ? " " + suffix : "")
    }

    function hourText(hours: real): string {
        const mins = Math.round((((hours % 24) + 24) % 24) * 60) % 1440
        return root.clockText(new Date(2000, 0, 1, Math.floor(mins / 60), mins % 60))
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
        function onIsIdleChanged() {
            root.catchUp()
            root._update()
        }
    }

    // NetworkManager parks every device for sleep and brings them back within seconds of wake
    Connections {
        target: Network
        function onConnectedChanged() { root.catchUp() }
    }

    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root.catchUp() }
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root.catchUp() }
    }

    function catchUp(): void {
        if (!clock.enabled
                || Qt.formatDateTime(new Date(), "yyyyMMddHHmm") === root._lastMinute) return
        root._resync = true
        root._resync = false
    }

    Connections {
        target: OverviewState
        function onActiveChanged() { if (!OverviewState.active) root._update() }
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
                cachedWeekday   = Qt.formatDateTime(current, "dddd")
                cachedMonthDay  = Qt.formatDateTime(current, "MMMM d")
                cachedWeek      = String(isoWeek(current))
            }
            cachedMinute = Qt.formatDateTime(current, "mm")
            hour24 = current.getHours()
            cachedHour = root.clockHour(current)
            cachedAmPm = root.clockSuffix(current)
        }
        if (!ShellSettings.barShowClock || !ShellSettings.showSeconds) {
            cachedSeconds = ""
        } else if (!Idle.isIdle || cachedSeconds.length === 0) {
            cachedSeconds = ":" + String(current.getSeconds()).padStart(2, "0")
        }
    }
}
