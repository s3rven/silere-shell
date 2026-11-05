pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string layout: Compositor.keyboardLayout
    readonly property bool available: root.layout.length > 0 || root._capsPath.length > 0
    property bool capsLock: false
    readonly property bool capsAvailable: root._capsPath.length > 0
    property string _capsPath: ""
    property int _capsFailures: 0
    readonly property bool _wanted: ShellSettings.barShowKeyboard && !Idle.isQuiet
    readonly property string shortLayout: {
        const name = root.layout.toLowerCase()
        const labels = { english: "EN", latvian: "LV", russian: "RU", german: "DE", french: "FR", spanish: "ES" }
        for (const word in labels) if (name.indexOf(word) >= 0) return labels[word]
        return root.layout.slice(0, 2).toUpperCase()
    }
    function refreshCaps(): void {
        if (!root._wanted) return
        if (root._capsPath.length > 0) _caps.reload()
        else if (!_findCaps.running) _findCaps.running = true
    }
    function _capsReadFailed(): void {
        // clearing FileView's path while hidden is not a lost keyboard
        if (!root._wanted) return
        root._capsPath = ""
        root.capsLock = false
    }
    on_WantedChanged: {
        if (root._wanted) root.refreshCaps()
        else if (_findCaps.running) _findCaps.running = false
    }
    Component.onCompleted: root.refreshCaps()
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open && !root._capsPath.length) root.refreshCaps()
        }
    }
    readonly property BoundedProcess _capsLookup: BoundedProcess {
        id: _findCaps
        timeoutMs: 2000
        command: ["bash", "-c", "for path in /sys/class/leds/*::capslock/brightness; do [ -r \"$path\" ] && { printf '%s\\n' \"$path\"; break; }; done; exit 0"]
        stdout: StdioCollector { id: _capsOut }
        onExited: code => {
            if (!root._wanted) return
            const path = _capsOut.text.trim()
            root._capsPath = _findCaps.completedSuccessfully(code)
                && /^\/sys\/class\/leds\/[^/]+::capslock\/brightness$/.test(path) ? path : ""
            root._capsFailures = root._capsPath.length > 0 ? 0 : Math.min(5, root._capsFailures + 1)
        }
    }
    // a keyboard can appear after login or vanish during a dock change; discovery resumes without opening the menu
    readonly property Timer _capsRetry: Timer {
        interval: Math.min(60000, 5000 * Math.pow(2, Math.max(0, root._capsFailures - 1)))
        running: root._wanted && root._capsPath.length === 0 && !_findCaps.running
        onTriggered: root.refreshCaps()
    }
    FileView {
        id: _caps
        path: root._wanted ? root._capsPath : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root.capsLock = _caps.text().trim() === "1"
        onLoadFailed: root._capsReadFailed()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root._wanted && root._capsPath.length > 0
        onTriggered: _caps.reload()
    }
}
