pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// self-update state for the shell (distinct from Updates.qml = distro packages). the daily
// update.sh check-only drops a flag when origin/main is ahead; watched via inotify so it surfaces in the bar
Singleton {
    id: root

    property int    count: 0
    property string summary: ""
    property bool   applying: false
    property string currentVersion: ""
    property real   lastCheckMs: 0
    property string lastCheckError: ""
    property string lastApplyError: ""
    property bool   timerSupported: false
    property bool   timerEnabled: false
    property bool   timerBusy: false

    readonly property bool pending: count > 0
    readonly property bool checking: _checkProc.running
    readonly property string label: count + (count === 1 ? " change ready" : " changes ready")
    readonly property string statusText: applying ? "Installing"
        : checking ? "Checking"
        : lastApplyError.length > 0 ? "Install failed"
        : lastCheckError.length > 0 ? "Check failed"
        : pending ? label
        : "Up to date"

    readonly property string _cacheDir: {
        const env = Quickshell.env("XDG_CACHE_HOME")
        const base = (env && String(env).length > 0)
            ? String(env)
            : String(Quickshell.env("HOME")) + "/.cache"
        return base + "/silere-shell"
    }
    readonly property string _script: Quickshell.shellDir + "/scripts/update.sh"

    function check(): void {
        if (checking || applying) return
        lastCheckError = ""
        _checkProc.exec(["bash", root._script])
    }

    function apply(): void {
        if (applying || _applyProc.running || !pending) return
        applying = true
        lastApplyError = ""
        _applyTimeout.restart()
        _applyProc.exec(["bash", root._script, "--apply"])
    }

    function refreshTimer(): void {
        if (!SystemTools.ready || _timerStatus.running || _timerSet.running) return
        _timerStatus.exec(["bash", root._script, "--timer-status"])
    }

    function setTimerEnabled(enabled: bool): void {
        if (timerBusy || !timerSupported) return
        timerBusy = true
        _timerSet.exec(["bash", root._script, enabled ? "--timer-enable" : "--timer-disable"])
    }

    // if --apply restarts the shell before Process reports back, clear applying so the bar isn't stuck
    Timer {
        id: _applyTimeout
        interval: 30000
        onTriggered: root.applying = false
    }

    Process {
        id: _versionProc
        command: ["bash", root._script, "--version"]
        stdout: StdioCollector { id: _versionOut }
        onExited: (code) => { if (code === 0) root.currentVersion = (_versionOut.text || "").trim() }
    }

    FileView {
        id: _flag
        path: root._cacheDir + "/update-pending"
        watchChanges: true
        printErrors:  false
        onLoaded:     root._parse(_flag.text())
        onLoadFailed: { root.count = 0; root.summary = ""; _applyTimeout.stop(); root.applying = false }
        onFileChanged: reload()
    }

    function _parse(t: string): void {
        const lines = (t || "").split(/\r?\n/)
        const n = parseInt((lines[0] || "").trim())
        root.count = isNaN(n) ? 0 : n
        root.summary = lines.slice(1).join("\n").trim()
    }

    function _lastOutputLine(out: string, err: string, fallback: string): string {
        const text = ((out || "") + "\n" + (err || "")).trim()
        const line = text.split(/\r?\n/).filter(function(s) { return s.length > 0 }).pop() || fallback
        return line.replace(/^silere-update:\s*/, "")
    }

    Process {
        id: _checkProc
        stdout: StdioCollector { id: _checkOut }
        stderr: StdioCollector { id: _checkErr }
        onExited: (code) => {
            root.lastCheckMs = Date.now()
            if (code === 0) {
                root.lastCheckError = ""
                root.lastApplyError = ""
            } else {
                root.lastCheckError = root._lastOutputLine(_checkOut.text, _checkErr.text, "Update check failed")
            }
            _flag.reload()
        }
    }

    Process {
        id: _applyProc
        stdout: StdioCollector { id: _applyOut }
        stderr: StdioCollector { id: _applyErr }
        onExited: (code) => {
            _applyTimeout.stop()
            root.applying = false
            if (code === 0) {
                root.lastApplyError = ""
                _flag.reload()
                _versionProc.running = true
            } else {
                root.lastApplyError = root._lastOutputLine(_applyOut.text, _applyErr.text, "Install failed")
            }
        }
    }

    Process {
        id: _timerStatus
        stdout: StdioCollector { id: _timerStatusOut }
        onExited: (code) => {
            if (code !== 0) return
            const lines = (_timerStatusOut.text || "").split(/\r?\n/)
            const state = {}
            for (let i = 0; i < lines.length; i++) {
                const p = lines[i].split("=")
                if (p.length === 2) state[p[0]] = p[1] === "1"
            }
            root.timerSupported = !!state.supported
            root.timerEnabled = !!state.enabled
        }
    }

    Process {
        id: _timerSet
        onExited: {
            root.timerBusy = false
            root.refreshTimer()
        }
    }

    // version + timer status only surface in Settings; probe once on first menu open, not every startup
    property bool _probed: false
    function _probe(): void {
        if (_probed) return
        _probed = true
        if (currentVersion.length === 0) _versionProc.running = true
        refreshTimer()
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._probe() }
    }
    // First read can race the tool scan; catch up once it lands.
    Connections {
        target: SystemTools
        function onReadyChanged() { if (root._probed) root.refreshTimer() }
    }
}
