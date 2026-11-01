pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property bool lockStateKnown: false
    property bool locked: false
    property bool busy: false
    property string lastError: ""
    readonly property bool _probeAvailable: SystemTools.ready && SystemTools.hasLoginctl && SystemTools.hasTimeout
    property int _generation: 0
    property int _statusGeneration: 0
    property int _waitGeneration: 0
    property bool _refreshPending: false
    readonly property bool canLockSleep: root.lockStateKnown && root._probeAvailable
        && Settings.lockCommand.length > 0 && Settings.suspendCommand.length > 0
    readonly property string readiness: root.canLockSleep
        ? "Lock and Sleep waits for the session to confirm it is locked."
        : "Lock and Sleep needs a locker and a login session that reports its lock state."

    function refresh(): void {
        if (!root._probeAvailable) return
        if (_status.running) { root._refreshPending = true; return }
        _refresh.restart()
    }
    Timer {
        id: _refresh
        interval: 0
        onTriggered: {
            if (!root._probeAvailable) return
            root._refreshPending = false
            root._statusGeneration = root._generation
            _status.running = true
        }
    }
    on_ProbeAvailableChanged: {
        root._generation++
        if (root._probeAvailable) root.refresh()
        else {
            _refresh.stop()
            root._refreshPending = false
            root.lockStateKnown = false
            root.locked = false
            if (_status.running) _status.running = false
            if (_before.running) _before.running = false
            if (_wait.running) _wait.running = false
        }
    }
    Component.onCompleted: root.refresh()
    Connections {
        target: SystemTools
        function onScanRevisionChanged() { root.refresh() }
    }
    function lockAndSleep(): bool {
        if (!root.canLockSleep || root.busy) return false
        if (Quickshell.env("SILERE_SANDBOX") === "1") return false
        root.busy = true
        root.lastError = ""
        root._waitGeneration = root._generation
        _before.running = true
        return true
    }
    function _cancelSleep(message: string): void {
        root.busy = false
        root.lastError = message
        // the menu closed on the press, and a lid shut on this stays awake and unlocked
        SystemAlerts.send("Sleep cancelled", message, "critical")
        root.refresh()
    }
    // read before locking: a hint a crashed locker left set would confirm the new lock before it is drawn
    BoundedProcess {
        id: _before
        timeoutMs: 4000
        command: ["bash", Quickshell.shellDir + "/scripts/session.sh", "status"]
        stdout: StdioCollector { id: _beforeOut }
        onExited: code => {
            // a cached hint may predate an unlock, so request the lock on every action
            Compositor.launch(Settings.lockCommand)
            const current = root._waitGeneration === root._generation && root.canLockSleep
            const state = _before.completedSuccessfully(code)
                ? (/(^|\n)locked=(yes|no)(\n|$)/.exec(_beforeOut.text) || [])[2] : undefined
            if (current && state === "no") _wait.running = true
            else root._cancelSleep(!current ? "Session readiness changed. Sleep was cancelled."
                : state === "yes" ? "The session was already marked locked, so the new lock could not be confirmed. Sleep was cancelled."
                : "Could not confirm screen lock. Sleep was cancelled.")
        }
    }
    BoundedProcess {
        id: _status
        timeoutMs: 4000
        command: ["bash", Quickshell.shellDir + "/scripts/session.sh", "status"]
        stdout: StdioCollector { id: _statusOut }
        onExited: code => {
            const current = root._statusGeneration === root._generation && root._probeAvailable
            if (current) {
                root.lockStateKnown = _status.completedSuccessfully(code)
                    && /(^|\n)locked=(yes|no)(\n|$)/.test(_statusOut.text)
                root.locked = root.lockStateKnown && /(^|\n)locked=yes(\n|$)/.test(_statusOut.text)
            }
            const refreshAgain = root._refreshPending || !current
            root._refreshPending = false
            if (refreshAgain) Qt.callLater(root.refresh)
        }
    }
    BoundedProcess {
        id: _wait
        timeoutMs: 15000
        command: ["bash", Quickshell.shellDir + "/scripts/session.sh", "wait-locked"]
        onExited: code => {
            const current = root._waitGeneration === root._generation && root.canLockSleep
            if (!_wait.completedSuccessfully(code) || !current) {
                root._cancelSleep(current ? "Could not confirm screen lock. Sleep was cancelled."
                    : "Session readiness changed. Sleep was cancelled.")
                return
            }
            root.busy = false
            SystemTools.runOrNotify(Settings.suspendCommand, "Suspend failed")
            root.refresh()
        }
    }
}
