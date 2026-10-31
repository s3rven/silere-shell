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
    readonly property bool _wanted: ShellSettings.barShowKeyboard && !Idle.isQuiet
    readonly property string shortLayout: {
        const name = root.layout.toLowerCase()
        const labels = { english: "EN", latvian: "LV", russian: "RU", german: "DE", french: "FR", spanish: "ES" }
        for (const word in labels) if (name.indexOf(word) >= 0) return labels[word]
        return root.layout.slice(0, 2).toUpperCase()
    }
    on_WantedChanged: if (root._wanted) {
        if (!root._capsPath.length) _findCaps.running = true
        else _caps.reload()
    }
    Component.onCompleted: if (root._wanted) _findCaps.running = true
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open && root._wanted && !root._capsPath.length) _findCaps.running = true
        }
    }
    BoundedProcess {
        id: _findCaps
        timeoutMs: 2000
        command: ["bash", "-c", "for path in /sys/class/leds/*::capslock/brightness; do [ -r \"$path\" ] && { printf '%s\\n' \"$path\"; break; }; done; exit 0"]
        stdout: StdioCollector { id: _capsOut }
        onExited: code => {
            const path = _capsOut.text.trim()
            root._capsPath = _findCaps.completedSuccessfully(code)
                && /^\/sys\/class\/leds\/[^/]+::capslock\/brightness$/.test(path) ? path : ""
        }
    }
    FileView {
        id: _caps
        path: root._wanted ? root._capsPath : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root.capsLock = _caps.text().trim() === "1"
        onLoadFailed: { root._capsPath = ""; root.capsLock = false }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root._wanted && root._capsPath.length > 0
        onTriggered: _caps.reload()
    }
}
