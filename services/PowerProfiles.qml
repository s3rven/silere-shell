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
        _correctiveRefreshPending = false
        _get._gen = root._writeGen
        _get.exec(["powerprofilesctl", "get"])
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
    Process {
        id: _get
        property int _gen: 0
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _getOut }
        onExited: (code) => {
            if (_set.running || _gen !== root._writeGen) return
            if (code === 0) {
                const p = (_getOut.text || "").trim()
                if (p.length > 0) { root.profile = p; root._getRetries = 0; return }
            }
            if (root.profile === "" && root.available && MenuState.open && root._getRetries < root._getRetryMax) {
                root._getRetries++
                _getRetry.restart()
            }
        }
    }
    Process {
        id: _set
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onExited: (code) => {
            if (code === 0) { root.lastError = ""; return }
            // the row re-reads the daemon, so a swallowed failure just flips the
            // label back with no reason given
            root.lastError = IconResolver.boundedText(
                _setErr.text.trim().split("\n").pop() || "Could not change the power mode", 160)
            root._correctiveRefreshPending = true
            root._getRetries = 0
            _getRetry.restart()
        }
    }
}
