pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int maxCommitDetail: 80
    readonly property int maxCommitSubjectChars: 512
    readonly property int maxPendingCount: 100000
    readonly property int maxStatusTextChars: 512
    readonly property int maxVersionTextChars: 128


    property int    count: 0
    property string summary: ""
    property bool   applying: false
    property string currentVersion: ""
    property string buildDate: ""
    property real   lastCheckMs: 0
    property string lastCheckError: ""
    property string lastApplyError: ""
    property bool   _flagLoaded: false
    property bool   _flagReadError: false
    property bool   _flagMalformed: false
    property bool   _checkedReadError: false
    readonly property string statusReadError: _flagReadError
        ? "Could not read pending update status"
        : _flagMalformed ? "Pending update status is malformed"
        : _checkedReadError ? "Could not read the last-check time" : ""
    property string timerError: ""
    property bool   _timerStatusError: false
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
    // a distro package ships no .git, so every git-backed control hides instead of erroring
    property bool   packaged: false
    readonly property bool versionBusy: _versionProc.running
    property string targetTag: ""
    property bool   targetVerified: false
    property var    pendingCommits: []
    // relative times are recomputed from this, refreshed on the events that can reveal them
    property real   _nowMs: 0

    readonly property bool pending: count > 0
    readonly property bool checking: _checkProc.running
    readonly property bool statusReady: _flagLoaded && _checkedLoaded
    readonly property string label: count + (count === 1 ? " change ready" : " changes ready")
    // "Up to date" is a claim about origin, so it needs a check to have reached it
    readonly property bool neverChecked: _checkedLoaded && lastCheckMs <= 0
    readonly property string statusText: applying ? "Installing"
        : checking ? "Checking"
        : lastApplyError.length > 0 ? "Install failed"
        : lastCheckError.length > 0 ? "Check failed"
        : statusReadError.length > 0 ? "Status unavailable"
        : pending ? label
        : !statusReady ? "Reading status"
        : neverChecked ? "Not checked yet"
        : "Up to date"

    readonly property bool upToDate: statusReady && lastCheckMs > 0
        && !applying && !checking && !pending
        && lastApplyError.length === 0 && lastCheckError.length === 0
        && statusReadError.length === 0

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
        if (root._flagReadError || root._flagMalformed) return root.statusReadError
        if (root.pending && !root.targetVerified) return "The release signature has not been verified"
        if (root.branch === "HEAD") return "The checkout is on a detached HEAD"
        if (root.branch.length > 0 && root.branch !== "main") return "The checkout is on branch " + root.branch
        if (root.localChanges) return "The checkout has local changes; scripts/repair.sh --apply clears them"
        return ""
    }

    readonly property string verificationDetail: !root.pending ? ""
        : root.targetVerified
            ? "Signature verified for " + (root.targetTag.length > 0 ? root.targetTag : "this release")
            : "Signature not verified"

    readonly property string lastCheckedText: DateTime.agoText(root.lastCheckMs, root._nowMs)

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
        if (checking || applying || packaged) return
        lastCheckError = ""
        _checkProc.exec(["bash", root._script])
    }

    function apply(): void {
        // keep fetch/check and merge/apply out of the same checkout at the same time even when this API is called outside the guarded settings UI
        if (checking || applying || _applyProc.running || !pending || !targetVerified
                || !versionReady || versionBusy || root.blockedReason.length > 0) return
        applying = true
        lastApplyError = ""
        _applyProc.exec(["bash", root._script, "--apply"])
    }

    function refreshTimer(): void {
        if (!SystemTools.ready || packaged || _timerStatus.running || _timerSet.running) return
        _timerStatus.exec(["bash", root._script, "--timer-status"])
    }

    function setTimerEnabled(enabled: bool): void {
        if (timerBusy || !timerSupported) return
        root._timerStatusError = false
        root.timerError = ""
        _timerSet.exec(["bash", root._script, enabled ? "--timer-enable" : "--timer-disable"])
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
        const out = Object.create(null)
        const lines = (t || "").split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const at = lines[i].indexOf("=")
            if (at > 0) out[lines[i].slice(0, at)] = lines[i].slice(at + 1).trim()
        }
        return out
    }

    function _countFrom(value): int {
        const text = String(value ?? "").trim()
        if (text.length === 0) return 0
        // update-pending lives in a user-writable cache. Reject partial numbers, signs and values large enough to make the status UI meaningless
        if (!/^[0-9]{1,6}$/.test(text)) return -1
        const count = Number(text)
        return isFinite(count) && count <= root.maxPendingCount ? count : -1
    }

    function _epochMsFrom(value): real {
        const text = String(value ?? "").trim()
        if (!/^[0-9]{1,12}$/.test(text)) return 0
        const seconds = Number(text)
        return isFinite(seconds) && seconds > 0 ? seconds * 1000 : 0
    }

    // history of what is already installed; the pending list disappears the moment it is applied
    property var  recentCommits: []
    property bool recentReady: false
    readonly property bool recentBusy: _recentProc.running

    function refreshRecent(): void {
        if (_recentProc.running) return
        _recentProc.running = true
    }

    onCurrentVersionChanged: root.recentReady = false

    Process {
        id: _recentProc
        command: ["bash", root._script, "--recent"]
        stdout: StdioCollector { id: _recentOut }
        onExited: (code) => {
            root.recentCommits = code === 0 ? root._parseCommits(_recentOut.text) : []
            root.recentReady = true
        }
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
            if ((kv.packaged ?? "") === "1") {
                root.packaged = true
                root.versionReady = false
                root.versionError = ""
                return
            }
            root.packaged = false
            const sha = SafeText.boundedText(kv.sha, root.maxVersionTextChars)
            const branch = SafeText.boundedText(kv.branch, root.maxVersionTextChars)
            const dirty = kv.dirty ?? ""
            if (sha.length === 0 || branch.length === 0
                    || (dirty !== "0" && dirty !== "1")) {
                root.versionReady = false
                root.versionError = "The checkout state could not be verified"
                return
            }
            root.currentVersion = sha
            root.buildDate = SafeText.boundedText(kv.date, root.maxVersionTextChars)
            root.versionTag = SafeText.boundedText(kv.tag, root.maxVersionTextChars)
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
        onLoaded: {
            root._flagReadError = false
            root._flagLoaded = true
            root._parse(_flag.text())
        }
        // a missing file means no pending update. Other failures are not safe to reinterpret as an empty file: retain the last state and warn
        onLoadFailed: error => {
            root._flagLoaded = true
            root._flagMalformed = false
            root._flagReadError = error !== FileViewError.FileNotFound
            if (!root._flagReadError) root._parse("")
        }
        onFileChanged: reload()
    }

    // until this has reported, a missing timestamp is unread state, not a missing check
    property bool _checkedLoaded: false

    FileView {
        id: _checked
        path: root._cacheDir.length > 0 ? root._cacheDir + "/update-checked" : ""
        watchChanges: true
        printErrors:  false
        onLoaded: {
            root._checkedReadError = false
            root.lastCheckMs = root._epochMsFrom(_checked.text())
            root._checkedLoaded = true
            root._touchNow()
        }
        onLoadFailed: error => {
            root._checkedReadError = error !== FileViewError.FileNotFound
            if (!root._checkedReadError) root.lastCheckMs = 0
            root._checkedLoaded = true
        }
        onFileChanged: reload()
    }

    function _parse(t: string): void {
        const lines = (t || "").split(/\r?\n/)
        const parsedCount = root._countFrom(lines[0])
        root._flagMalformed = parsedCount < 0
        root.count = Math.max(0, parsedCount)
        let rest = lines.slice(1)
        let tag = ""
        let verified = false
        if (root._flagMalformed) rest = []
        // a flag file written before this line existed carries commits here instead
        if ((rest[0] ?? "").startsWith("target ")) {
            // match exactly what update.sh writes. A cache edit may change what the UI says, but must never make malformed metadata look verified
            const target = /^target ([0-9a-f]{7,64}) (v[0-9]+\.[0-9]+\.[0-9]+) verified$/
                .exec(rest[0].trim())
            if (target) {
                tag = target[2]
                verified = true
            }
            rest = rest.slice(1)
        }
        root.targetTag = SafeText.boundedText(tag, root.maxVersionTextChars)
        root.targetVerified = verified
        root.summary = rest.slice(0, root.maxCommitDetail).map(function(line) {
            return SafeText.boundedText(line, root.maxCommitSubjectChars + 80)
        }).join("\n").trim()
        root.pendingCommits = root._parseCommits(root.summary)
    }

    function _parseCommits(t: string): var {
        const out = []
        const lines = (t || "").split(/\r?\n/)
        for (let i = 0; i < lines.length && out.length < root.maxCommitDetail; i++) {
            const line = lines[i].trim()
            if (line.length === 0) continue
            const at = line.indexOf(" ")
            if (at > 0) out.push({
                hash: SafeText.boundedText(line.slice(0, at), 64),
                subject: SafeText.boundedText(line.slice(at + 1).trim(), root.maxCommitSubjectChars)
            })
            else out.push({
                hash: "",
                subject: SafeText.boundedText(line, root.maxCommitSubjectChars)
            })
        }
        return out
    }

    function _lastOutputLine(out: string, err: string, fallback: string): string {
        const text = ((out || "") + "\n" + (err || "")).trim()
        const line = text.split(/\r?\n/).filter(function(s) { return s.length > 0 }).pop() || fallback
        return SafeText.boundedText(line.replace(/^silere-update:\s*/, ""),
            root.maxStatusTextChars)
    }

    BoundedProcess {
        id: _checkProc
        timeoutMs: 120000
        stdout: StdioCollector { id: _checkOut }
        stderr: StdioCollector { id: _checkErr }
        onTimeoutReached: root.lastCheckError = "Update check timed out"
        onExited: (code) => {
            if (_checkProc.timedOut) {
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

    BoundedProcess {
        id: _applyProc
        timeoutMs: 180000
        stdout: StdioCollector { id: _applyOut }
        stderr: StdioCollector { id: _applyErr }
        onTimeoutReached: root.lastApplyError = "Update install timed out"
        onExited: (code) => {
            root.applying = false
            if (_applyProc.timedOut) return
            if (code === 0) {
                root.lastApplyError = ""
                _flag.reload()
                root._refreshVersion()
            } else {
                root.lastApplyError = root._lastOutputLine(_applyOut.text, _applyErr.text, "Install failed")
                // the authoritative script may discover a branch/dirty-state change after the UI was opened; refresh the displayed block
                root._refreshVersion()
            }
        }
    }

    BoundedProcess {
        id: _timerStatus
        timeoutMs: 10000
        stdout: StdioCollector { id: _timerStatusOut }
        stderr: StdioCollector { id: _timerStatusErr }
        onTimeoutReached: {
            root._timerStatusError = true
            root.timerError = "Update timer check timed out"
        }
        onExited: (code) => {
            if (timedOut) return
            if (code !== 0) {
                root._timerStatusError = true
                root.timerError = root._lastOutputLine(
                    _timerStatusOut.text, _timerStatusErr.text,
                    "Could not check the update timer")
                return
            }
            const kv = root._parseKv(_timerStatusOut.text)
            root.timerSupported = kv.supported === "1"
            root.timerEnabled = kv.enabled === "1"
            root.nextCheckMs = root._epochMsFrom(kv.next)
            if (root._timerStatusError) root.timerError = ""
            root._timerStatusError = false
            root._touchNow()
        }
    }

    BoundedProcess {
        id: _timerSet
        timeoutMs: 15000
        stderr: StdioCollector { id: _timerSetErr }
        onTimeoutReached: root.timerError = "Update timer change timed out"
        onExited: (code) => {
            if (timedOut) {
                root.refreshTimer()
                return
            }
            // the switch is bound to the unit's real state, so a swallowed failure just flips it back with no reason given
            root.timerError = code === 0 ? ""
                : SafeText.boundedText(
                    _timerSetErr.text.trim().split("\n").pop()
                        || "Could not change the update timer",
                    root.maxStatusTextChars)
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
