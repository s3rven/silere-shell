pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// power-profiles-daemon frontend. No monitor process: the profile is read once
// per menu open and writes are optimistic, so idle cost is zero.
Singleton {
    id: root

    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _get.running
    property string profile: ""   // "" until the first successful read

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced" : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    // Bumped on every cycle() so a get() issued before it can tell, on exit,
    // that it's answering a question a newer write has already overtaken —
    // _set.running alone misses this when the set finishes first.
    property int _writeGen: 0

    function refresh(): void {
        if (!available || _get.running) return
        _get._gen = root._writeGen
        _get.exec(["powerprofilesctl", "get"])
    }

    function cycle(): void {
        // _set.running guard: exec while a set is in flight drops the write
        // but the optimistic profile would still flip — UI and daemon diverge.
        if (!available || profile === "" || _set.running) return
        const order = ["balanced", "performance", "power-saver"]
        const next = order[(order.indexOf(profile) + 1) % order.length]
        profile = next   // optimistic; a failed set re-syncs below
        root._writeGen++
        _set.exec(["powerprofilesctl", "set", next])
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root.refresh() }
    }
    // First read can race the tool scan; catch up once it lands.
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready && MenuState.open) root.refresh() }
    }
    Component.onCompleted: Qt.callLater(root.refresh)

    Process {
        id: _get
        property int _gen: 0
        stdout: StdioCollector { id: _getOut }
        onExited: (code) => {
            if (code !== 0) return
            // A set in flight, or one that already landed after this read started,
            // means this read predates (or no longer matches) the new profile;
            // applying it would clobber the optimistic value. The set's own
            // onExited re-syncs on failure, so dropping the stale read is safe.
            if (_set.running || _gen !== root._writeGen) return
            const p = (_getOut.text || "").trim()
            if (p.length > 0) root.profile = p
        }
    }
    Process {
        id: _set
        onExited: (code) => { if (code !== 0) root.refresh() }
    }
}
