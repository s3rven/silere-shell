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

    function _flush(): void { _marksFile.setText(JSON.stringify({ marks: Object.keys(root.marks) })) }
    Timer { id: _saveTimer; interval: 400; onTriggered: root._flush() }
    // blocking write (blockWrites) so a toggle inside the debounce window survives quit/reload
    Component.onDestruction: if (_saveTimer.running) { _saveTimer.stop(); _flush() }

    FileView {
        id: _marksFile
        path: ShellSettings._configDir + "/calendar-marks.json"
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onLoaded: {
            try {
                const j = JSON.parse(_marksFile.text() || "{}")
                const next = {}
                if (Array.isArray(j.marks))
                    for (let i = 0; i < j.marks.length; i++)
                        if (/^\d{4}-\d{1,2}-\d{1,2}$/.test(String(j.marks[i]))) next[j.marks[i]] = true
                root.marks = next
            } catch (e) { console.warn("silere-shell: bad calendar-marks.json, ignoring:", String(e)) }
        }
    }
}
