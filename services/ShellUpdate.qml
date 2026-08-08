pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int    count: 0
    property string summary: ""
    property bool   applying: false
    property string currentVersion: ""
    property string buildDate: ""
    property real   lastCheckMs: 0
    property string lastCheckError: ""
    property string lastApplyError: ""
    property bool   timerSupported: false
    property bool   timerEnabled: false
    readonly property bool timerBusy: _timerStatus.running || _timerSet.running
    property real   nextCheckMs: 0
    property string versionTag: ""
    property int    versionAhead: 0
    property string branch: ""
    property bool   localChanges: false
    property bool   versionReady: false
    property string versionError: ""
    readonly property bool versionBusy: _versionProc.running
    property string targetVersion: ""
    property string targetTag: ""
    property var    pendingCommits: []
    property bool   _checkTimedOut: false
    property bool   _applyTimedOut: false
    // relative times are recomputed from this, refreshed on the events that can reveal them
    property real   _nowMs: 0

    readonly property bool pending: count > 0
    readonly property bool checking: _checkProc.running
    readonly property string label: count + (count === 1 ? " change ready" : " changes ready")
    readonly property string statusText: applying ? "Installing"
        : checking ? "Checking"
        : lastApplyError.length > 0 ? "Install failed"
        : lastCheckError.length > 0 ? "Check failed"
        : pending ? label
        : "Up to date"

    readonly property bool upToDate: !applying && !checking && !pending
        && lastApplyError.length === 0 && lastCheckError.length === 0

    readonly property string versionLabel: versionTag.length === 0
        ? (currentVersion.length > 0 ? "#" + currentVersion : "")
        : versionAhead > 0 ? versionTag + " +" + versionAhead : versionTag

    readonly property string targetLabel: targetTag.length > 0 && targetTag !== versionTag
        ? targetTag : ""

    readonly property string versionDetail: {
        const parts = []
        if (root.currentVersion.length > 0) parts.push("#" + root.currentVersion)
        if (root.branch.length > 0) parts.push(root.branch === "HEAD" ? "detached HEAD" : root.branch)
        if (root.buildDate.length > 0) parts.push("built " + root.buildDate)
        if (root.localChanges) parts.push("local changes")
        return parts.join(" · ")
    }

    // states --apply refuses to run in; reported before the button is pressed rather than after
    readonly property string blockedReason: {
        if (!root.versionReady) return root.versionBusy
            ? "Checking checkout state"
            : root.versionError.length > 0 ? root.versionError
            : "The checkout state has not been verified"
        if (root.branch === "HEAD") return "The checkout is on a detached HEAD"
        if (root.branch.length > 0 && root.branch !== "main") return "The checkout is on branch " + root.branch
        if (root.localChanges) return "The checkout has uncommitted local changes"
        return ""
    }

    readonly property string lastCheckedText: {
        if (root.lastCheckMs <= 0) return ""
        const secs = Math.max(0, Math.round((root._nowMs - root.lastCheckMs) / 1000))
        if (secs < 90) return "just now"
        if (secs < 3600) return Math.floor(secs / 60) + " min ago"
        if (secs < 86400) return Math.floor(secs / 3600) + " h ago"
        const days = Math.floor(secs / 86400)
        return days <= 1 ? "yesterday" : days + " days ago"
    }

    readonly property string nextCheckText: {
        if (!root.timerEnabled || root.nextCheckMs <= 0) return ""
        const secs = Math.round((root.nextCheckMs - root._nowMs) / 1000)
        if (secs <= 60) return "Next check due now"
        if (secs < 3600) return "Next check in " + Math.round(secs / 60) + " min"
        if (secs < 172800) return "Next check in " + Math.round(secs / 3600) + " h"
        return "Next check in " + Math.round(secs / 86400) + " days"
    }

    // the bar pill renders statusText and must not grow with it; this longer form is menu-only
    readonly property string statusDetail: {
        if (!root.upToDate) return root.statusText
        if (root.lastCheckedText.length > 0) return root.statusText + " · checked " + root.lastCheckedText
        if (root.buildDate.length > 0) return root.statusText + " · built " + root.buildDate
        return root.statusText
    }

    readonly property string _cacheDir: {
        const configured = String(Quickshell.env("XDG_CACHE_HOME") || "").trim()
        if (configured.startsWith("/")) return configured + "/silere-shell"
        const home = String(Quickshell.env("HOME") || "").trim()
        return home.startsWith("/") ? home + "/.cache/silere-shell" : ""
    }
    readonly property string _script: Quickshell.shellDir + "/scripts/update.sh"

    function check(): void {
        if (checking || applying) return
        lastCheckError = ""
        _checkTimedOut = false
        _checkTimeout.restart()
        _checkProc.exec(["bash", root._script])
    }

    function apply(): void {
        // Keep fetch/check and merge/apply out of the same checkout at the same
        // time even when this API is called outside the guarded settings UI.
        if (checking || applying || _applyProc.running || !pending
                || !versionReady || versionBusy) return
        applying = true
        lastApplyError = ""
        _applyTimedOut = false
        _applyTimeout.restart()
        _applyProc.exec(["bash", root._script, "--apply"])
    }

    function refreshTimer(): void {
        if (!SystemTools.ready || _timerStatus.running || _timerSet.running) return
        _timerStatus.exec(["bash", root._script, "--timer-status"])
    }

    function setTimerEnabled(enabled: bool): void {
        if (timerBusy || !timerSupported) return
        _timerSet.exec(["bash", root._script, enabled ? "--timer-enable" : "--timer-disable"])
    }

    Timer {
        id: _checkTimeout
        interval: 120000
        onTriggered: {
            if (!_checkProc.running) return
            root._checkTimedOut = true
            root.lastCheckError = "Update check timed out"
            _checkProc.running = false
        }
    }

    Timer {
        id: _applyTimeout
        interval: 180000
        onTriggered: {
            if (!_applyProc.running) return
            root._applyTimedOut = true
            root.applying = false
            root.lastApplyError = "Update install timed out"
            _applyProc.running = false
        }
    }

    function _touchNow(): void { root._nowMs = Date.now() }

    Timer {
        interval: 60000
        repeat: true
        running: MenuState.settingsActive
            && MenuState.settingsSection === "updates"
        onTriggered: root._touchNow()
    }

    function _parseKv(t: string): var {
        const out = ({})
        const lines = (t || "").split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const at = lines[i].indexOf("=")
            if (at > 0) out[lines[i].slice(0, at)] = lines[i].slice(at + 1).trim()
        }
        return out
    }

    function _refreshVersion(): void {
        if (_versionProc.running) return
        root.versionReady = false
        root.versionError = ""
        _versionProc.running = true
    }

    Process {
        id: _versionProc
        command: ["bash", root._script, "--version"]
        stdout: StdioCollector { id: _versionOut }
        onExited: (code) => {
            if (code !== 0) {
                root.versionReady = false
                root.versionError = "The checkout state could not be verified"
                return
            }
            const kv = root._parseKv(_versionOut.text)
            const sha = kv.sha ?? ""
            const branch = kv.branch ?? ""
            const dirty = kv.dirty ?? ""
            if (sha.length === 0 || branch.length === 0
                    || (dirty !== "0" && dirty !== "1")) {
                root.versionReady = false
                root.versionError = "The checkout state could not be verified"
                return
            }
            root.currentVersion = sha
            root.buildDate = kv.date ?? ""
            root.versionTag = kv.tag ?? ""
            const ahead = parseInt(kv.ahead ?? "0")
            root.versionAhead = isNaN(ahead) ? 0 : ahead
            root.branch = branch
            root.localChanges = dirty === "1"
            root.versionError = ""
            root.versionReady = true
        }
    }

    FileView {
        id: _flag
        path: root._cacheDir.length > 0 ? root._cacheDir + "/update-pending" : ""
        watchChanges: true
        printErrors:  false
        onLoaded:     root._parse(_flag.text())
        // --apply clears the flag before restarting, so a missing file proves nothing
        onLoadFailed: root._parse("")
        onFileChanged: reload()
    }

    FileView {
        id: _checked
        path: root._cacheDir.length > 0 ? root._cacheDir + "/update-checked" : ""
        watchChanges: true
        printErrors:  false
        onLoaded: {
            const secs = parseInt((_checked.text() || "").trim())
            root.lastCheckMs = isNaN(secs) || secs <= 0 ? 0 : secs * 1000
            root._touchNow()
        }
        onLoadFailed: root.lastCheckMs = 0
        onFileChanged: reload()
    }

    function _parse(t: string): void {
        const lines = (t || "").split(/\r?\n/)
        const n = parseInt((lines[0] || "").trim())
        root.count = isNaN(n) ? 0 : n
        let rest = lines.slice(1)
        let target = ""
        let tag = ""
        // a flag file written before this line existed carries commits here instead
        if ((rest[0] ?? "").startsWith("target ")) {
            const parts = rest[0].slice(7).trim().split(/\s+/)
            target = parts[0] ?? ""
            tag = parts[1] ?? ""
            rest = rest.slice(1)
        }
        root.targetVersion = target
        root.targetTag = tag
        root.summary = rest.join("\n").trim()
        root.pendingCommits = root._parseCommits(root.summary)
    }

    function _parseCommits(t: string): var {
        const out = []
        const lines = (t || "").split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.length === 0) continue
            const at = line.indexOf(" ")
            if (at > 0) out.push({ hash: line.slice(0, at), subject: line.slice(at + 1).trim() })
            else out.push({ hash: "", subject: line })
        }
        return out
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
            _checkTimeout.stop()
            if (root._checkTimedOut) {
                root._checkTimedOut = false
                _flag.reload()
                return
            }
            if (code === 0) {
                root.lastCheckError = ""
                root.lastApplyError = ""
            } else {
                root.lastCheckError = root._lastOutputLine(_checkOut.text, _checkErr.text, "Update check failed")
            }
            _flag.reload()
            _checked.reload()
            root._refreshVersion()
        }
    }

    Process {
        id: _applyProc
        stdout: StdioCollector { id: _applyOut }
        stderr: StdioCollector { id: _applyErr }
        onExited: (code) => {
            _applyTimeout.stop()
            root.applying = false
            if (root._applyTimedOut) {
                root._applyTimedOut = false
                return
            }
            if (code === 0) {
                root.lastApplyError = ""
                _flag.reload()
                root._refreshVersion()
            } else {
                root.lastApplyError = root._lastOutputLine(_applyOut.text, _applyErr.text, "Install failed")
                // The authoritative script may discover a branch/dirty-state
                // change after the UI was opened; refresh the displayed block.
                root._refreshVersion()
            }
        }
    }

    Process {
        id: _timerStatus
        stdout: StdioCollector { id: _timerStatusOut }
        onExited: (code) => {
            if (code !== 0) return
            const kv = root._parseKv(_timerStatusOut.text)
            root.timerSupported = kv.supported === "1"
            root.timerEnabled = kv.enabled === "1"
            const next = parseInt(kv.next ?? "0")
            root.nextCheckMs = isNaN(next) || next <= 0 ? 0 : next * 1000
            root._touchNow()
        }
    }

    Process {
        id: _timerSet
        onExited: {
            root.refreshTimer()
        }
    }

    property bool _probed: false
    function _probe(): void {
        _probed = true
        _touchNow()
        _refreshVersion()
        refreshTimer()
    }
    function _probeIfVisible(): void {
        if (MenuState.settingsActive && MenuState.settingsSection === "updates")
            _probe()
    }
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (!MenuState.open) return
            root._touchNow()
            root._probeIfVisible()
        }
        function onSettingsActiveChanged() { root._probeIfVisible() }
        function onSettingsSectionChanged() { root._probeIfVisible() }
    }
    Connections {
        target: SystemTools
        function onReadyChanged() { if (root._probed) root.refreshTimer() }
    }
}
