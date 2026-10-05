pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string directory: XdgPaths.configHome.length > 0
        ? XdgPaths.configHome + "/silere-shell" : ""
    readonly property string settingsPath: directory.length > 0
        ? directory + "/settings.json" : ""
    // history is message text, not configuration, so it stays out of a config folder kept in a dotfiles repo
    readonly property string stateDirectory: XdgPaths.stateHome.length > 0
        ? XdgPaths.stateHome + "/silere-shell" : ""
    readonly property string notificationsPath: stateDirectory.length > 0
        ? stateDirectory + "/notifications.json" : ""
    readonly property string _legacyNotificationsPath: directory.length > 0
        ? directory + "/notifications.json" : ""

    property bool ready: false
    property string _error: ""
    readonly property string error: _error
    readonly property int maxDirectoryAttempts: 4

    property int _directoryFailures: 0

    function directoryRetryDelay(attempt: int): int {
        return Math.min(8000, 1000 * Math.pow(2, Math.max(0, attempt - 1)))
    }

    function _startDirectoryAttempt(): void {
        if (_mkdir.running) return
        if (root.directory.length === 0) {
            root._error = "No configuration directory is available."
            return
        }
        // a forced recheck follows a failed write: stop advertising readiness while it reruns
        root.ready = false
        _mkdir.running = true
    }

    function ensureDirectory(force): void {
        if (_mkdir.running || (root.ready && force !== true)) return
        if (_mkdirRetry.running && force !== true) return
        if (force === true || root._directoryFailures >= root.maxDirectoryAttempts) {
            _mkdirRetry.stop()
            root._directoryFailures = 0
        }
        root._startDirectoryAttempt()
    }

    Timer {
        id: _mkdirRetry
        interval: root.directoryRetryDelay(root._directoryFailures)
        repeat: false
        onTriggered: root._startDirectoryAttempt()
    }

    property var _hardened: ({})

    function hardenFile(path: string): void {
        // only files owned by this store may be chmodded. Keep the path as a separate argv entry so even unusual XDG paths never become syntax
        if (path.length === 0
                || (path !== root.settingsPath && path !== root.notificationsPath)) return
        // an atomic write lands an owner-only replacement, so one chmod per path per session covers it; _mkdir re-hardens after a failed write
        if (root._hardened[path] === true) return
        root._hardened[path] = true
        Quickshell.execDetached(["bash", "-c",
            "[ ! -L \"$1\" ] && chmod 0600 -- \"$1\"", "bash", path])
    }

    BoundedProcess {
        id: _mkdir
        timeoutMs: 10000
        command: ["bash", "-c",
            // without the exits, the trailing file check's status hides a failed mkdir
            "umask 077; for d in \"$1\" \"$2\"; do [ -n \"$d\" ] || continue; " +
            "[ ! -L \"$d\" ] || exit 1; " +
            "mkdir -m 0700 -p -- \"$d\" || exit $?; " +
            "chmod 0700 -- \"$d\" || exit $?; done; " +
            // history used to live in the config folder; a failed move leaves that file where it is and starts a fresh one
            "if [ -n \"$4\" ] && [ -f \"$5\" ] && [ ! -L \"$5\" ] && [ ! -e \"$4\" ] && [ ! -L \"$4\" ]; then " +
            "mv -- \"$5\" \"$4\" || true; fi; " +
            "for f in \"$3\" \"$4\"; do [ -n \"$f\" ] || continue; " +
            "[ ! -e \"$f\" ] || [ -L \"$f\" ] || chmod 0600 -- \"$f\" || exit $?; done",
            "bash", root.directory, root.stateDirectory, root.settingsPath,
            root.notificationsPath, root._legacyNotificationsPath]
        onExited: code => {
            if (code === 0) {
                _mkdirRetry.stop()
                root._directoryFailures = 0
                root.ready = true
                root._error = ""
                return
            }

            root.ready = false
            root._error = "Could not create " + root.directory + "."
            root._directoryFailures++
            if (root._directoryFailures < root.maxDirectoryAttempts)
                _mkdirRetry.restart()
            console.warn("silere-shell: failed to create config directory:",
                root.directory)
        }
    }

    Component.onCompleted: root.ensureDirectory()
}
