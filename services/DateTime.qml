pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    function clockNeeded(barClock: bool, overview: bool, scheduled: bool,
            menuClock: bool, calendarOpen: bool): bool {
        return (barClock && !overview) || scheduled || menuClock || calendarOpen
    }

    // set by ClockDemand: what shows the time sits above this service, so it is told, never read from here
    property bool wanted: true
    property bool overviewOpen: false

    readonly property int _stepMs: ShellSettings.barShowClock && ShellSettings.showSeconds
        && !Idle.isIdle && !root.overviewOpen ? 1000 : 60000
    // epoch arithmetic, since every zone's offset is whole minutes. Quickshell's SystemClock rounds in local time, and
    // in a DST fall-back's repeated hour that put its next tick an hour back: it fired every millisecond for the hour
    function nextTickMs(nowMs: real, stepMs: int): real { return nowMs + stepMs - nowMs % stepMs }
    property date currentDate: new Date()
    // a monotonic timer stops in suspend, so wall time past its deadline gives a lower bound on sleep
    signal woke(real sleptMs)
    property real _dueMs: 0
    Timer { id: clock; onTriggered: root._tick() }

    // a minute sample keeps the format previews from updating on every second tick
    property date minuteSample: new Date()

    // english keeps its own formats; elsewhere names come from the locale, as in the calendar, and so does the order
    readonly property var locale: Qt.locale()
    readonly property bool englishDates: root.locale.name === "C" || root.locale.name.startsWith("en")
    function formatDate(d, format: string): string {
        return root.englishDates ? Qt.formatDateTime(d, format) : root.locale.toString(d, format)
    }
    // the day and month, with the year when asked, cut from the locale's long date format: "d. MMMM" in German,
    // "M月d日" in Japanese. A suffix glued to the last field stays ("24." in Hungarian, "24日"); a comma does not
    function localDateFormat(longFormat: string, withYear: bool): string {
        const tokens = String(longFormat).match(/'(?:[^']|'')*'|d+|M+|y+|[^'dMy]+/g) || []
        let first = -1, last = -1
        for (let i = 0; i < tokens.length; i++) {
            if (!/^(d{1,2}|M+)$/.test(tokens[i]) && !(withYear && /^y+$/.test(tokens[i]))) continue
            if (first < 0) first = i
            last = i
        }
        if (first < 0) return withYear ? "d MMMM yyyy" : "d MMMM"
        const glued = /^[^\s,'dMy]+/.exec(tokens[last + 1] ?? "")
        return tokens.slice(first, last + 1).join("") + (glued ? glued[0].replace(/,.*$/, "") : "")
    }
    readonly property string monthDayFormat: root.englishDates ? "MMMM d"
        : root.localDateFormat(root.locale.dateFormat(Locale.LongFormat), false)
    readonly property string monthDayShortFormat: root.englishDates ? "MMM dd" : root.monthDayFormat.replace("MMMM", "MMM")
    readonly property string fullDateShortFormat: root.englishDates ? "MMM d, yyyy"
        : root.localDateFormat(root.locale.dateFormat(Locale.LongFormat), true).replace("MMMM", "MMM")

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

    Component.onCompleted: if (root.wanted) root._tick(); else root._update()

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
        target: ShellSettings
        function onClock12hChanged() { root._refreshMinute() }
        function onShowSecondsChanged() { root._update() }
        function onBarShowClockChanged() { root._refreshMinute() }
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (root.wanted) root.catchUp()
            else root._update()
        }
    }

    onWantedChanged: if (root.wanted) root._tick(); else { clock.stop(); root._dueMs = 0 }
    on_StepMsChanged: if (root.wanted) root._tick()
    function _tick(): void {
        const step = root._stepMs
        const now = Date.now()
        const late = root._dueMs > 0 ? now - root._dueMs : 0
        root._dueMs = root.nextTickMs(now, step)
        clock.interval = root._dueMs - now
        clock.restart()
        root.currentDate = new Date(now - now % step)
        root._update()
        if (late > 30000 || late < -62000) root.woke(Math.max(0, late))
    }
    function catchUp(): void { if (root.wanted) root._tick() }

    function _refreshMinute(): void {
        root._lastMinute = ""
        root._update()
    }

    function _update(current = root.currentDate): void {
        const minute = Qt.formatDateTime(current, "yyyyMMddHHmm")
        if (minute !== _lastMinute) {
            _lastMinute = minute
            minuteSample = current
            const day = minute.slice(0, 8)
            if (day !== _lastDay) {
                _lastDay        = day
                cachedDayName   = root.formatDate(current, "ddd") + " "
                cachedDateCore  = root.formatDate(current, root.monthDayShortFormat)
                cachedWeekday   = root.formatDate(current, "dddd")
                cachedMonthDay  = root.formatDate(current, root.monthDayFormat)
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
