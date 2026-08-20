pragma Singleton

import QtQuick
import Quickshell.Io
import "../config"

AnchoredPopupState {
    id: root

    function toggleAt(x: real, screen, source): void {
        if (open) { close(); return }
        openAt(x, screen, source)
    }

    IpcHandler {
        target: "calendar"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.openUnanchored()
        }
        function close(): void { root.close() }
    }

    property var marks: ({})
    property bool _saveDirty: false
    property string persistenceError: ""

    function markKey(y: int, m: int, d: int): string { return y + "-" + (m + 1) + "-" + d }
    function _validMarkKey(value): bool {
        const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(value))
        if (!match) return false
        const year = Number(match[1])
        const month = Number(match[2])
        const day = Number(match[3])
        if (year < 1 || month < 1 || month > 12 || day < 1) return false
        const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
        const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= days[month - 1]
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
        serialize: () => JSON.stringify({ marks: Object.keys(root.marks) })
        onLoaded: raw => {
            try {
                const trimmed = raw.trim()
                const j = JSON.parse(trimmed || "{}")
                const next = {}
                if (Array.isArray(j.marks))
                    for (let i = 0; i < j.marks.length; i++)
                        if (root._validMarkKey(j.marks[i])) next[j.marks[i]] = true
                root.marks = next
                _store.writeAllowed = true
                _store.lastSavedText = trimmed
                root.persistenceError = ""
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
