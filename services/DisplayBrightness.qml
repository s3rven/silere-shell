pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: ShellSettings.ddcBrightnessEnabled
        && SystemTools.hasDdcutil && SystemTools.hasTimeout
    readonly property bool _wanted: root.available && !Idle.isIdle && MenuState.open
        && (MenuState.homeActive || (MenuState.settingsActive && MenuState.settingsSection === "interface"))
    property var displays: []
    property var values: ({})
    property string _scanError: ""
    property string _writeError: ""
    readonly property string lastError: root._writeError || root._scanError
    readonly property bool scanning: _scan.running
    property var _queued: ({})
    property string _writingKey: ""
    property int _generation: 0
    property int _scanGeneration: 0
    property int _writeGeneration: 0
    property bool _refreshPending: false
    property real _lastScan: 0

    function parseDisplays(raw: string): var {
        const result = []
        for (const line of raw.split(/\r?\n/)) {
            const f = line.split("\t")
            if (f.length !== 5 || !/^card[0-9]+-[A-Za-z0-9-]+$/.test(f[0])
                    || !/^[0-9]+$/.test(f[1]) || !/^[a-f0-9]{64}$/.test(f[2])) continue
            const current = Number(f[3]), maximum = Number(f[4])
            if (!isFinite(current) || !isFinite(maximum) || maximum <= 0 || current < -1 || current > maximum) continue
            result.push({ key: f[0] + ":" + f[2], connector: f[0], label: f[0].replace(/^card[0-9]+-/, ""),
                bus: f[1], identity: f[2], percent: Math.round(100 * current / maximum) })
        }
        return result
    }
    function disabled(key: string): bool {
        return ("," + ShellSettings.ddcDisabledDisplays + ",").indexOf("," + key + ",") >= 0
    }
    function setEnabled(key: string, on: bool): void {
        const keys = ShellSettings.ddcDisabledDisplays.split(",").filter(k => k.length > 0 && k !== key)
        if (!on) keys.push(key)
        ShellSettings.ddcDisabledDisplays = keys.join(",")
        root.invalidate()
    }
    function refresh(force: bool): void {
        if (!root._wanted) return
        const age = Date.now() - root._lastScan
        if (!force && age >= 0 && age < 60000) return
        if (_scan.running || _write.running) { root._refreshPending = true; return }
        root._refreshPending = false
        root._scanGeneration = root._generation
        _scan.running = true
    }
    function invalidate(): void {
        root._generation++
        root._lastScan = 0
        root._queued = ({})
        root._refreshPending = false
        _debounce.stop()
        root.displays = []
        root.values = ({})
        root._scanError = ""
        root._writeError = ""
        // running commands still verify their captured EDID; no later queued write survives
        Qt.callLater(root.refresh, true)
    }
    on_WantedChanged: if (root._wanted) root.refresh(root._refreshPending)
    onAvailableChanged: root.invalidate()
    Connections {
        target: Quickshell
        function onScreensChanged() { root.invalidate() }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { if (!Idle.isIdle) root.invalidate() }
    }
    function levelFor(key: string): real { return Number(root.values[key] ?? 50) }
    function setPercent(key: string, percent: real): void {
        if (!root.available || root.disabled(key) || !isFinite(percent)
                || Quickshell.env("SILERE_SANDBOX") === "1") return
        if (!root.displays.some(d => d.key === key)) return
        const next = Math.max(1, Math.min(100, Math.round(percent)))
        root.values = Object.assign({}, root.values, { [key]: next })
        root._queued = Object.assign({}, root._queued, { [key]: next })
        _debounce.restart()
    }
    function _applyNext(): void {
        if (_scan.running || _write.running || !root.available) return
        const key = Object.keys(root._queued)[0]
        if (!key) return
        const percent = root._queued[key]
        const queued = Object.assign({}, root._queued)
        delete queued[key]
        root._queued = queued
        const display = root.displays.find(d => d.key === key)
        if (!display || root.disabled(key)) { Qt.callLater(root._applyNext); return }
        root._writingKey = key
        root._writeGeneration = root._generation
        _write.command = ["bash", Quickshell.shellDir + "/scripts/display-brightness.sh", "write",
            display.connector, display.bus, display.identity, String(percent)]
        _write.running = true
    }
    function _resume(): void {
        if (root._refreshPending) root.refresh(true)
        root._applyNext()
    }
    Timer { id: _debounce; interval: 100; onTriggered: root._applyNext() }
    BoundedProcess {
        id: _scan
        timeoutMs: 20000
        command: ["bash", Quickshell.shellDir + "/scripts/display-brightness.sh", "list", ShellSettings.ddcDisabledDisplays]
        stdout: StdioCollector { id: _scanOut }
        onExited: code => {
            if (root._scanGeneration !== root._generation) {
                root._refreshPending = true
            } else if (_scan.completedSuccessfully(code)) {
                root.displays = root.parseDisplays(_scanOut.text)
                const levels = {}
                // a slider can move during discovery; keep its latest queued value
                for (const display of root.displays)
                    levels[display.key] = root._queued[display.key] ?? display.percent
                root.values = levels
                root._scanError = ""
                root._lastScan = Date.now()
            } else root._scanError = "Could not read external displays. Check DDC/CI support and I2C permissions."
            Qt.callLater(root._resume)
        }
    }
    BoundedProcess {
        id: _write
        timeoutMs: 15000
        onExited: code => {
            const key = root._writingKey
            root._writingKey = ""
            if (root._writeGeneration !== root._generation) {
                root._refreshPending = true
            } else if (!_write.completedSuccessfully(code)) {
                root._writeError = "Display brightness could not be changed."
                // the failed display must be read back; other displays still own their queued changes
                const queued = Object.assign({}, root._queued)
                delete queued[key]
                root._queued = queued
                root._lastScan = 0
            } else {
                root._writeError = ""
            }
            if (root._lastScan === 0) root._refreshPending = true
            Qt.callLater(root._resume)
        }
    }
}
