pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _get.running || _set.running || _getRetry.running
    property string profile: ""
    property string lastError: ""

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced"
                                  : profile.length > 0        ? profile.replace(/-/g, " ") : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    property int _writeGen: 0
    property bool _correctiveRefreshPending: false

    property int _getRetries: 0
    readonly property int _getRetryMax: 4
    readonly property var _knownProfiles: ["balanced", "performance", "power-saver"]
    Timer {
        id: _getRetry
        interval: 600
        onTriggered: {
            if (_get.running || _set.running) {
                restart()
                return
            }
            root.refresh()
        }
    }

    function refresh(): void {
        if (!available || _get.running || _set.running) return
        _get._corrective = root._correctiveRefreshPending
        _correctiveRefreshPending = false
        _get._gen = root._writeGen
        _get.exec(["powerprofilesctl", "get"])
    }

    function _queueCorrectiveRefresh(): void {
        root._correctiveRefreshPending = true
        root._getRetries = 0
        _getRetry.restart()
    }

    function _parseProfile(value): string {
        const profile = SafeText.singleLineText(value, 64)
        return root._knownProfiles.indexOf(profile) >= 0 ? profile : ""
    }

    function cycle(): void {
        // _set.running guard: exec while a set's in flight drops the write but still flips the optimistic profile — UI and daemon diverge
        if (!available || profile === "" || _set.running) return
        const order = ["balanced", "performance", "power-saver"]
        const next = order[(order.indexOf(profile) + 1) % order.length]
        profile = next
        root.lastError = ""
        root._writeGen++
        _set.exec(["powerprofilesctl", "set", next])
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open) { root._getRetries = 0; root.refresh() }
            else if (!root._correctiveRefreshPending) _getRetry.stop()
        }
    }
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready && MenuState.open) root.refresh() }
    }
    BoundedProcess {
        id: _get
        property int _gen: 0
        property bool _corrective: false
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _getOut }
        onTimeoutReached: root.lastError = "Power mode check timed out"
        onExited: (code) => {
            if (_set.running || _gen !== root._writeGen) return
            if (code === 0) {
                const p = root._parseProfile(_getOut.text)
                if (p.length > 0) {
                    root.profile = p
                    root._getRetries = 0
                    root._correctiveRefreshPending = false
                    if (root.lastError === "Power mode check timed out"
                            || root.lastError === "Could not verify the power mode")
                        root.lastError = ""
                    return
                }
            }
            const shouldRetry = root.profile === "" || _corrective
            if (shouldRetry && root.available && (MenuState.open || _corrective)
                    && root._getRetries < root._getRetryMax) {
                root._getRetries++
                root._correctiveRefreshPending = _corrective
                _getRetry.restart()
                return
            }
            if (shouldRetry && !timedOut)
                root.lastError = "Could not verify the power mode"
        }
    }
    BoundedProcess {
        id: _set
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onTimeoutReached: root.lastError = "Power mode change timed out"
        onExited: (code) => {
            if (timedOut) {
                root._queueCorrectiveRefresh()
                return
            }
            if (code === 0) {
                root.lastError = ""
                root._queueCorrectiveRefresh()
                return
            }
            // the row re-reads the daemon, so a swallowed failure just flips the
            // label back with no reason given
            root.lastError = SafeText.boundedText(
                _setErr.text.trim().split("\n").pop() || "Could not change the power mode", 160)
            root._queueCorrectiveRefresh()
        }
    }
}
