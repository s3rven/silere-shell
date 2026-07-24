pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _get.running || _getRetry.running
    property string profile: ""

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced" : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    property int _writeGen: 0

    property int _getRetries: 0
    readonly property int _getRetryMax: 4
    Timer { id: _getRetry; interval: 600; onTriggered: root.refresh() }

    function refresh(): void {
        if (!available || _get.running) return
        _get._gen = root._writeGen
        _get.exec(["powerprofilesctl", "get"])
    }

    function cycle(): void {
        // _set.running guard: exec while a set's in flight drops the write but still flips the optimistic profile — UI and daemon diverge
        if (!available || profile === "" || _set.running) return
        const order = ["balanced", "performance", "power-saver"]
        const next = order[(order.indexOf(profile) + 1) % order.length]
        profile = next
        root._writeGen++
        _set.exec(["powerprofilesctl", "set", next])
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open) { root._getRetries = 0; root.refresh() }
            else _getRetry.stop()
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
        onExited: (code) => { if (code !== 0) root.refresh() }
    }
}
