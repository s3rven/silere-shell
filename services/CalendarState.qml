pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property ShellScreen triggerScreen: null

    function toggleAt(x: real, screen): void {
        if (open) { close(); return }
        anchorX = x
        if (screen) triggerScreen = screen
        open = true
    }
    function close(): void { if (open) open = false; triggerScreen = null }

    IpcHandler {
        target: "calendar"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.triggerScreen = null
            root.open = true
        }
        function close(): void { root.close() }
    }

    property var marks: ({})
    property bool _savePendingForDir: false
    property bool _saveDirty: false
    property string _lastSavedJson: ""
    property int _saveFailureCount: 0

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
        ConfigStore.ensureDirectory()
        _saveTimer.restart()
    }

    function _flush(): void {
        if (!ConfigStore.ready) {
            root._savePendingForDir = true
            ConfigStore.ensureDirectory()
            return
        }
        const json = JSON.stringify({ marks: Object.keys(root.marks) })
        if (json === root._lastSavedJson) return
        root._savePendingForDir = false
        root._lastSavedJson = json
        _marksFile.setText(json + (root._saveFailureCount % 2 === 0 ? "\n" : "\n\n"))
    }
    Timer { id: _saveTimer; interval: 400; onTriggered: root._flush() }
    Timer {
        id: _saveRetry
        interval: Math.min(8000, 1000 * Math.pow(2, Math.max(0, root._saveFailureCount - 1)))
        onTriggered: root._flush()
    }
    // blocking write (blockWrites) so a toggle inside the debounce window survives quit/reload
    Component.onDestruction: {
        const pending = root._saveDirty || _saveTimer.running || _saveRetry.running
        _saveTimer.stop()
        _saveRetry.stop()
        if (pending) root._flush()
    }

    Connections {
        target: ConfigStore
        function onReadyChanged() {
            if (ConfigStore.ready && root._savePendingForDir) root._flush()
        }
    }

    FileView {
        id: _marksFile
        path: ConfigStore.calendarMarksPath
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onLoaded: {
            try {
                const raw = (_marksFile.text() || "").trim()
                const j = JSON.parse(raw || "{}")
                const next = {}
                if (Array.isArray(j.marks))
                    for (let i = 0; i < j.marks.length; i++)
                        if (root._validMarkKey(j.marks[i])) next[j.marks[i]] = true
                root.marks = next
                root._lastSavedJson = raw
            } catch (e) { console.warn("silere-shell: bad calendar-marks.json, ignoring:", String(e)) }
        }
        onSaved: {
            root._saveDirty = false
            root._saveFailureCount = 0
            _saveRetry.stop()
        }
        onSaveFailed: (error) => {
            root._lastSavedJson = ""
            root._saveFailureCount++
            console.warn("silere-shell: failed to save calendar marks:", error)
            if (root._saveFailureCount <= 3) _saveRetry.restart()
        }
    }
}
