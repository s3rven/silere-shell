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

    function _owned(path: string): bool {
        if (path === root.settingsPath || path === root.calendarMarksPath) return true
        if (root.directory.length === 0) return false
        const prefix = root.directory + "/settings."
        const suffix = ".bak.json"
        if (!path.startsWith(prefix) || !path.endsWith(suffix)) return false
        // a tag carrying a slash would chmod its way out of the store directory
        return /^[a-z0-9.-]+$/i.test(path.slice(prefix.length, path.length - suffix.length))
    }

    function hardenFile(path: string): void {
        // Only files owned by this store may be chmodded. Keep the path as a
        // separate argv entry so even unusual XDG paths never become syntax.
        if (path.length === 0 || !root._owned(path)) return
        Quickshell.execDetached(["bash", "-c",
            "[ ! -L \"$1\" ] && chmod 0600 -- \"$1\"", "bash", path])
    }

    Process {
        id: _mkdir
        command: ["bash", "-c",
            "umask 077; mkdir -m 0700 -p -- \"$1\" && chmod 0700 -- \"$1\"; " +
            "for f in \"$2\" \"$3\"; do " +
            "[ ! -e \"$f\" ] || [ -L \"$f\" ] || chmod 0600 -- \"$f\"; done",
            "bash", root.directory, root.settingsPath, root.calendarMarksPath]
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
