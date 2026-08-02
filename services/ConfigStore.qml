pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string directory: {
        const configured = String(Quickshell.env("XDG_CONFIG_HOME") || "").trim()
        if (configured.startsWith("/")) return configured + "/silere-shell"
        const home = String(Quickshell.env("HOME") || "").trim()
        return home.startsWith("/") ? home + "/.config/silere-shell" : ""
    }
    readonly property string settingsPath: directory.length > 0
        ? directory + "/settings.json" : ""
    readonly property string calendarMarksPath: directory.length > 0
        ? directory + "/calendar-marks.json" : ""

    property bool ready: false
    property string _error: ""
    readonly property string error: _error

    function ensureDirectory(): void {
        if (root.ready || _mkdir.running) return
        if (root.directory.length === 0) {
            root._error = "No configuration directory is available."
            return
        }
        _mkdir.running = true
    }

    Process {
        id: _mkdir
        command: ["mkdir", "-m", "0700", "-p", root.directory]
        onExited: code => {
            root.ready = code === 0
            root._error = code === 0 ? ""
                : "Could not create " + root.directory + "."
            if (code !== 0)
                console.warn("silere-shell: failed to create config directory:",
                    root.directory)
        }
    }

    Component.onCompleted: root.ensureDirectory()
}
