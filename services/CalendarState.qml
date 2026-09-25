pragma Singleton

import QtQuick
import Quickshell.Io
import "../config"

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

    function leadingDays(year: int, month: int): int {
        return (new Date(year, month, 1).getDay() - firstWeekday + 7) % 7
    }

    function weekForRow(year: int, month: int, row: int): int {
        // the thursday in a displayed row determines its iso week, even on a sunday-first grid
        const thursday = (4 - firstWeekday + 7) % 7
        return DateTime.isoWeek(new Date(year, month, 1 - leadingDays(year, month) + row * 7 + thursday))
    }

    property var marks: ({})
    property bool _saveDirty: false
    property string persistenceError: ""

    function markKey(y: int, m: int, d: int): string { return y + "-" + (m + 1) + "-" + d }
    // "" for anything that is not a real date; a hand-written 2026-09-05 still marks the 5th
    function _canonicalMarkKey(value): string {
        const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(value))
        if (!match) return ""
        const year = Number(match[1])
        const month = Number(match[2])
        const day = Number(match[3])
        if (year < 1 || month < 1 || month > 12 || day < 1) return ""
        const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
        const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= days[month - 1] ? root.markKey(year, month - 1, day) : ""
    }
    function toggleMark(y: int, m: int, d: int): void {
        const k = markKey(y, m, d)
        const next = {}
        for (const key in marks) if (key !== k) next[key] = true
        if (marks[k] !== true) next[k] = true
        marks = next
        _saveDirty = true
        // one click is one discrete change: write through rather than sit in the
        // debounce window, which a SIGTERM would discard with no hook to save it
        _store.flush(false)
    }

    // blocking write (blockWrites) so a toggle inside the debounce window survives a reload;
    // SIGTERM tears the process down without running this, so it is no guard against a kill
    Component.onDestruction: {
        const pending = root._saveDirty || _store.pending
        _store.stop()
        if (pending) _store.flush(true)
    }

    PersistedFile {
        id: _store
        path: ConfigStore.calendarMarksPath
        watchChanges: true
        writeAllowed: false
        serialize: () => JSON.stringify({ __version: 1, marks: Object.keys(root.marks) })
        onLoaded: raw => {
            try {
                const trimmed = raw.trim()
                // our own write echoing back through the watcher
                if (_store.writeAllowed && trimmed === _store.lastSavedText) return
                const j = JSON.parse(trimmed || "{}")
                if (j === null || typeof j !== "object" || Array.isArray(j)
                        || (j.marks !== undefined && !Array.isArray(j.marks)))
                    throw new Error("unexpected shape")
                const version = Number(j.__version ?? 0)
                const fromFuture = isFinite(version) && version > 1
                const next = {}
                if (Array.isArray(j.marks))
                    for (let i = 0; i < j.marks.length; i++) {
                        const key = root._canonicalMarkKey(j.marks[i])
                        if (key.length > 0) next[key] = true
                    }
                root.marks = next
                _store.writeAllowed = !fromFuture
                _store.lastSavedText = trimmed
                if (fromFuture) {
                    root.persistenceError = "Calendar marks are from a newer version. The existing file was left untouched."
                    console.warn("silere-shell: calendar-marks.json is from a newer version; keeping it as it is")
                } else {
                    root.persistenceError = ""
                }
            } catch (e) {
                // a file we could not read may still hold marks; writing this session's set over it loses them
                _store.writeAllowed = false
                root.persistenceError = "Could not read calendar marks. The existing file was left untouched."
                console.warn("silere-shell: bad calendar-marks.json, ignoring:", String(e))
            }
        }
        onLoadFailed: error => {
            _store.writeAllowed = error === FileViewError.FileNotFound
            root.persistenceError = _store.writeAllowed ? ""
                : "Could not read calendar marks. The existing file was left untouched."
        }
        onSaved: {
            root._saveDirty = false
            root.persistenceError = ""
        }
        onSaveFailed: error => {
            root.persistenceError = "Could not save calendar marks. Your latest change may be lost."
            console.warn("silere-shell: failed to save calendar marks:", error)
        }
    }
}
