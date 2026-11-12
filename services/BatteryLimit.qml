pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// a battery's charge limit: upower sets it for the active session, and the kernel says whether one is on
Singleton {
    id: root

    // the preview leaves the desktop's battery alone, as it does the keyboard light
    readonly property bool toolAvailable: SystemTools.hasBusctl && !SystemTools.preview
    // read once Home first shows a battery: a limit moves only from here or the firmware, so the
    // details read it again as they open instead of each opening of Home
    readonly property bool _wanted: root.toolAvailable && Battery.available && MenuState.open
        && MenuState.homeActive && !Idle.isIdle
    property bool _listed: false
    property var devices: []
    property string pendingNative: ""
    // the switch shows what was asked while the write is out, and steps back if it fails
    property bool pendingOn: false
    property string lastError: ""
    // the battery a failed write belongs to; empty when the failure was the read
    property string errorNative: ""
    // a write moves the revision on, so a read that began before it cannot publish the old state over it
    property int _revision: 0
    property int _generation: 0
    property bool _rescanQueued: false

    function parseDevices(raw: string): var {
        const out = []
        for (const line of String(raw || "").split(/\r?\n/)) {
            const f = line.split("\t")
            if (f.length !== 4 || !/^\/org\/freedesktop\/UPower\/devices\/battery_[A-Za-z0-9_]+$/.test(f[0])
                    || !/^[A-Za-z0-9_.:-]{1,64}$/.test(f[1]) || (f[2] !== "on" && f[2] !== "off")
                    || !/^[0-9]{1,2}$/.test(f[3]) || out.some(d => d.nativePath === f[1])) continue
            out.push({ path: f[0], nativePath: f[1], on: f[2] === "on", stopsAt: Number(f[3]) })
        }
        return out
    }

    function forNative(nativePath: string): var {
        return root.devices.find(d => d.nativePath === nativePath) ?? null
    }

    // what the switch does: the stop the kernel names, or only the intent where it names none (Lenovo)
    function describe(limit): string {
        if (!limit) return ""
        return limit.stopsAt > 0 ? "Stops at " + limit.stopsAt + "% to slow wear" : "Stops short of full to slow wear"
    }

    function rescan(): void {
        if (!root.toolAvailable) return
        if (_list.running || _write.running) { root._rescanQueued = true; return }
        root._rescanQueued = false
        _list.revision = root._revision
        _list.generation = root._generation
        _list.running = true
    }

    // the details opening: whatever changed the limit meanwhile, the firmware included, shows now
    function refresh(): void {
        // a machine with no limit to set does not grow one between two openings
        if (root._listed && root.devices.length === 0) return
        root.lastError = ""
        root.errorNative = ""
        root.rescan()
    }

    function setEnabled(nativePath: string, on: bool): void {
        const limit = root.forNative(nativePath)
        if (!root.toolAvailable || !limit || limit.on === on || root.pendingNative.length > 0
                || Quickshell.env("SILERE_SANDBOX") === "1") return
        root._revision++
        root.lastError = ""
        root.errorNative = ""
        root.pendingOn = on
        root.pendingNative = nativePath
        _write.generation = root._generation
        _write.nativePath = nativePath
        _write.exec(["bash", Quickshell.shellDir + "/scripts/battery-limit.sh", "write",
            limit.path, on ? "on" : "off", nativePath])
    }

    function _publish(row): void {
        if (!row) return
        root.devices = root.devices.map(d => d.nativePath === row.nativePath ? row : d)
    }

    on_WantedChanged: if (root._wanted && !root._listed) root.rescan()
    Component.onCompleted: if (root._wanted && !root._listed) root.rescan()
    onToolAvailableChanged: {
        root._generation++
        root._listed = false
        root.devices = []
        root.lastError = ""
        root.errorNative = ""
        root.pendingNative = ""
        if (root._wanted) Qt.callLater(root.rescan)
    }

    readonly property BoundedProcess _list: BoundedProcess {
        property int revision: 0
        property int generation: -1
        timeoutMs: 10000
        command: ["bash", Quickshell.shellDir + "/scripts/battery-limit.sh", "list"]
        stdout: StdioCollector { id: _listOut }
        onExited: code => {
            if (generation === root._generation && revision === root._revision && root.toolAvailable) {
                const complete = completedSuccessfully(code)
                const found = root.parseDevices(_listOut.text)
                // a battery that answered keeps its switch when another could not be read
                if (complete || found.length > 0) {
                    root.devices = found
                    root._listed = true
                }
                if (!complete) {
                    root.lastError = "The charge limit could not be read. Check UPower."
                    root.errorNative = ""
                }
            } else if (generation === root._generation) {
                root._rescanQueued = true
            }
            if (root._rescanQueued) Qt.callLater(root.rescan)
        }
    }
    BoundedProcess {
        id: _write
        property int generation: -1
        property string nativePath: ""
        // as long as the script waits on a polkit prompt, and a little more
        timeoutMs: 65000
        stdout: StdioCollector { id: _writeOut }
        onExited: code => {
            if (generation === root._generation && root.toolAvailable) {
                const row = root.parseDevices(_writeOut.text).find(d => d.nativePath === nativePath) ?? null
                root._publish(row)
                if (!completedSuccessfully(code)) {
                    root.errorNative = nativePath
                    root.lastError = code === 4 ? "The charge limit did not change. The firmware may not allow it."
                        : code === 3 ? "The battery changed meanwhile. Try again."
                        : "The charge limit could not be changed. Check UPower permissions."
                    // a refused write printed nothing, so what the kernel holds now is read again
                    if (!row) root._rescanQueued = true
                }
            }
            root.pendingNative = ""
            root._revision++
            if (root._rescanQueued) Qt.callLater(root.rescan)
        }
    }
}
