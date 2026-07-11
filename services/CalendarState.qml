pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// decoupled open/anchor state for the calendar popup (clock pokes, popup reads); anchorX = clock's screen-x
Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property var  triggerScreen: null

    function toggleAt(x: real, screen): void {
        if (open) { close(); return }   // also clears triggerScreen, like close()
        anchorX = x
        if (screen) triggerScreen = screen
        open = true
    }
    function close(): void { if (open) open = false; triggerScreen = null }

    // day marks: "y-m-d" → true, reassigned wholesale so cell bindings refresh; file-backed to survive restarts
    property var marks: ({})
    property bool _savePendingForDir: false
    property string _lastSavedJson: ""
    property int _saveFailureCount: 0

    function markKey(y: int, m: int, d: int): string { return y + "-" + (m + 1) + "-" + d }
    function toggleMark(y: int, m: int, d: int): void {
        const k = markKey(y, m, d)
        const next = {}
        for (const key in marks) if (key !== k) next[key] = true
        if (marks[k] !== true) next[k] = true
        marks = next
        ShellSettings._ensureConfigDir()
        _saveTimer.restart()
    }

    function _flush(): void {
        if (!ShellSettings._configDirReady) {
            root._savePendingForDir = true
            ShellSettings._ensureConfigDir()
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
    Component.onDestruction: if (_saveTimer.running) { _saveTimer.stop(); _flush() }

    Connections {
        target: ShellSettings
        function on_ConfigDirReadyChanged() {
            if (ShellSettings._configDirReady && root._savePendingForDir) root._flush()
        }
    }

    FileView {
        id: _marksFile
        path: ShellSettings._configDir + "/calendar-marks.json"
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
                        if (/^\d{4}-\d{1,2}-\d{1,2}$/.test(String(j.marks[i]))) next[j.marks[i]] = true
                root.marks = next
                root._lastSavedJson = raw
            } catch (e) { console.warn("silere-shell: bad calendar-marks.json, ignoring:", String(e)) }
        }
        onSaved: {
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
