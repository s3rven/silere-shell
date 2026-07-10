pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// power-profiles-daemon frontend; no monitor process — read once per menu open, writes optimistic, zero idle cost
Singleton {
    id: root

    readonly property bool available: SystemTools.hasPowerProfilesCtl
    // syncing spans the retry backoff so a transient failure reads "Checking…" not "Unavailable" between attempts
    readonly property bool syncing: _get.running || _getRetry.running
    property string profile: ""   // "" until the first successful read

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced" : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    // bumped on every cycle() so a get() can tell on exit that a newer write overtook it — _set.running alone misses this if the set finished first
    property int _writeGen: 0

    // bounded read retry: a failed/empty get self-heals instead of sticking on "Unavailable"; only while a consumer's open, zero idle cost
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
        profile = next   // optimistic; a failed set re-syncs below
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
    // First read can race the tool scan; catch up once it lands.
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
            // a set in flight or freshly landed means this read predates the new profile and would clobber the optimistic value; the set re-syncs on failure, so dropping it is safe
            if (_set.running || _gen !== root._writeGen) return
            if (code === 0) {
                const p = (_getOut.text || "").trim()
                if (p.length > 0) { root.profile = p; root._getRetries = 0; return }
            }
            // failed/empty read: retry while the menu's open and still no profile, so a hiccup doesn't stick on "Unavailable"
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
