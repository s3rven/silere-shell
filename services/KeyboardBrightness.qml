pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool toolAvailable: SystemTools.hasBusctl
    readonly property bool _wanted: root.toolAvailable && !Idle.isIdle && MenuState.open
        && (MenuState.homeActive || (MenuState.settingsActive
            && (MenuState.settingsSection === "interface" || MenuState.settingsSection === "updates")))
    property var devices: []
    property string preferredKey: ""
    readonly property var selected: root.devices.find(d => d.key === root.preferredKey) || root.devices[0] || null
    readonly property string key: root.selected ? root.selected.key : ""
    readonly property int maximum: root.selected ? root.selected.maximum : 0
    readonly property bool ready: root.toolAvailable && root.maximum > 0
    property int currentLevel: 0
    property int _confirmedLevel: 0
    property string _currentKey: ""
    property string _readError: ""
    property string _writeError: ""
    readonly property string lastError: root._writeError || root._readError
    readonly property var choices: root.devices.map((d, i) => ({ value: d.key, label: "Keyboard light " + (i + 1) }))
    property int _generation: 0
    property int _discoveryGeneration: 0
    property int _revision: 0
    property int _publishingRevision: 0
    property bool _queued: false
    property bool _refreshPending: false

    function parseDevices(raw: string): var {
        const out = []
        for (const line of raw.split(/\r?\n/)) {
            const f = line.split("\t")
            if (f.length !== 4 || !/^\/org\/freedesktop\/UPower\/KbdBacklight(\/[A-Za-z0-9_]+)?$/.test(f[0])
                    || !/^[0-9]+$/.test(f[1]) || !/^[0-9]+$/.test(f[2]) || !f[3]) continue
            const level = Number(f[1]), maximum = Number(f[2])
            if (!isFinite(level) || !isFinite(maximum) || maximum <= 0 || maximum > 2147483647 || level > maximum) continue
            const key = f[0] + "|" + f[3]
            if (!out.some(d => d.key === key)) out.push({ key: key, path: f[0], identity: f[3], level: level, maximum: maximum })
        }
        return out
    }

    function rescan(): void {
        if (!root.toolAvailable) return
        if (_list.running) { root._refreshPending = true; return }
        root._refreshPending = false
        _list.revision = root._revision
        _list.generation = root._discoveryGeneration
        _list.running = true
    }

    on_WantedChanged: if (root._wanted) root.rescan()
    Component.onCompleted: if (root._wanted) root.rescan()
    onToolAvailableChanged: {
        root._discoveryGeneration++
        if (!root.toolAvailable) {
            root.devices = []
            root._readError = ""
            root._writeError = ""
            root._refreshPending = false
        } else if (root._wanted) Qt.callLater(root.rescan)
    }

    function _select(): void {
        const selected = root.selected
        const nextKey = selected ? selected.key : ""
        if (nextKey !== root._currentKey) {
            root._generation++
            root._revision++
            root._currentKey = nextKey
            root._queued = false
            _apply.stop()
            root._writeError = ""
            root.currentLevel = selected ? selected.level : 0
            root._confirmedLevel = root.currentLevel
        } else if (!root._queued && !_set.running && root._publishingRevision === root._revision && root.selected) {
            root.currentLevel = root.selected.level
            root._confirmedLevel = root.currentLevel
        }
    }
    onSelectedChanged: root._select()
    onKeyChanged: root._select()

    function setLevel(level: real): void {
        if (!root.ready || !isFinite(level) || Quickshell.env("SILERE_SANDBOX") === "1") return
        const next = Math.max(0, Math.min(root.maximum, Math.round(level)))
        if (root.currentLevel === next) return
        root._revision++
        root.currentLevel = next
        root._queued = true
        _apply.restart()
    }

    readonly property Timer _applyTimer: Timer {
        id: _apply
        interval: 75
        onTriggered: {
            if (!root.ready || !root._queued || _set.running) return
            root._queued = false
            _set.key = root.key
            _set.generation = root._generation
            _set.level = root.currentLevel
            _set.exec(["bash", Quickshell.shellDir + "/scripts/keyboard-brightness.sh", "write",
                root.selected.path, String(root.currentLevel), root.selected.identity])
        }
    }
    readonly property Timer _pollTimer: Timer {
        interval: root.ready ? 3000 : 15000
        running: root._wanted
        repeat: true
        onTriggered: root.rescan()
    }
    BoundedProcess {
        id: _list
        property int revision: 0
        property int generation: -1
        timeoutMs: 15000
        command: ["bash", Quickshell.shellDir + "/scripts/keyboard-brightness.sh", "list"]
        stdout: StdioCollector { id: _listOut }
        onExited: code => {
            if (root.toolAvailable && generation === root._discoveryGeneration) {
                const complete = completedSuccessfully(code)
                const found = root.parseDevices(_listOut.text)
                // each row is one light read to the end; one that failed must not take the others' sliders with it
                if (complete || found.length > 0) {
                    root._publishingRevision = revision
                    root.devices = found
                }
                root._readError = complete ? "" : found.length > 0 ? "Some keyboard lights could not be read. Check UPower."
                    : "Could not read keyboard lighting. Check UPower."
            }
            if (root._refreshPending && root._wanted) Qt.callLater(root.rescan)
        }
    }
    BoundedProcess {
        id: _set
        property string key: ""
        property int generation: -1
        property int level: 0
        timeoutMs: 8000
        onExited: code => {
            if (generation === root._generation && key === root.key && root.toolAvailable) {
                if (completedSuccessfully(code)) {
                    root._writeError = ""
                    root._confirmedLevel = level
                }
                else {
                    root._writeError = "Keyboard light could not be changed. Check UPower permissions."
                    root._queued = false
                    _apply.stop()
                    root.currentLevel = root._confirmedLevel
                }
            }
            // a read that began before this write landed still carries the level from before it
            root._revision++
            if (root._queued) _apply.restart()
            else root.rescan()
        }
    }
}
