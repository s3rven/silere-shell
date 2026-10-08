pragma Singleton

import QtQuick
import Quickshell.Io

AnchoredPopupState {
    id: root

    readonly property bool armed: true

    function toggleAt(x: real, screen, source): void {
        if (open) { close(); return }
        openAt(x, screen, source)
    }

    IpcHandler {
        target: "calendar"

        function toggle(): string {
            if (root.open) { root.close(); return "ok" }
            root.openUnanchored()
            return root.open ? "ok"
                : "error: the calendar stays closed while the session is idle or the overview is open"
        }
        function close(): void { root.close() }
    }

    readonly property int firstWeekday: weekStartFor(
        ShellSettings.calendarWeekStart, Qt.locale().firstDayOfWeek)

    function weekStartFor(mode: string, localeDay: int): int {
        if (mode === "sunday") return 0
        if (mode === "locale") return Math.max(0, Math.min(6, localeDay))
        return 1
    }

    function weekdayAt(column: int): int { return (firstWeekday + column) % 7 }

    readonly property var workingDays: Qt.locale().weekDays

    function weekdayLabelFor(day: int, locale): string {
        return locale.standaloneDayName(day, Locale.ShortFormat)
    }

    function weekendFor(day: int, weekdays): bool {
        if (!Array.isArray(weekdays) || weekdays.length === 0) return day === 0 || day === 6
        return weekdays.indexOf(day) < 0
    }

    function isWeekend(day: int): bool { return root.weekendFor(day, root.workingDays) }

    function leadingDays(year: int, month: int): int {
        return (new Date(year, month, 1).getDay() - firstWeekday + 7) % 7
    }

    function weekForRow(year: int, month: int, row: int): int {
        // the thursday in a displayed row determines its iso week, even on a sunday-first grid
        const thursday = (4 - firstWeekday + 7) % 7
        return DateTime.isoWeek(new Date(year, month, 1 - leadingDays(year, month) + row * 7 + thursday))
    }
}
