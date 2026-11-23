pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool supported: SystemTools.hasDdcutil && SystemTools.hasTimeout && !SystemTools.preview
    readonly property bool available: ShellSettings.ddcBrightnessEnabled && root.supported
    readonly property bool _menuWanted: MenuState.open
        && (MenuState.homeActive || (MenuState.settingsActive
            && (MenuState.settingsSection === "devices" || MenuState.settingsSection === "updates")))
    readonly property bool _wanted: root.available && !Idle.isIdle
        && (ShellSettings.barShowBrightness || root._menuWanted)
    property var displays: []
    readonly property var controllableDisplays: root.displays.filter(d =>
        d.percent >= 0 && !d.unreadable && !root.disabled(d.key))
    // the bar's brightness widget shows for these alone, on a computer with no backlight of its own
    readonly property bool hasControl: root.available && root.controllableDisplays.length > 0
    property var values: ({})
    property string _scanError: ""
    property string _writeError: ""
    readonly property string lastError: root._writeError || root._scanError
    // the wait for a second read counts: until then "nothing found" or a warning would be a guess
    readonly property bool scanning: _scan.running || _settleRetry.running
    property var _queued: ({})
    property string _writingKey: ""
    property int _generation: 0
    property int _scanGeneration: 0
    property int _writeGeneration: 0
    property bool _refreshPending: false
    property real _lastScan: 0
    property bool _settleRetried: false

    // screens: Quickshell's, so a display reads as Settings names it elsewhere ("DELL U2723QE · DP-2"); a connector no
    // screen shows (switched off in the compositor) keeps its port
    function parseDisplays(raw: string, screens): var {
        const result = []
        for (const line of raw.split(/\r?\n/)) {
            const f = line.split("\t")
            if (f.length !== 5 || !/^card[0-9]+-[A-Za-z0-9-]+$/.test(f[0])
                    || !/^[0-9]+$/.test(f[1]) || !/^[a-f0-9]{64}$/.test(f[2])) continue
            const current = Number(f[3]), maximum = Number(f[4]), port = f[0].replace(/^card[0-9]+-/, "")
            const screen = (screens || []).find(s => s && s.name === port)
            // -1: switched off, so not read; -2: it answered on none of its buses
            if (!isFinite(current) || !isFinite(maximum) || maximum <= 0 || current < -2 || current > maximum) continue
            result.push({ key: f[0] + ":" + f[2], connector: f[0], label: screen ? Monitors.label(screen, screens) : port,
                bus: f[1], identity: f[2], unreadable: current === -2, maximum,
                percent: current < 0 ? -1 : Math.round(100 * current / maximum) })
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
        root._rescan()
    }
    // not invalidate(): emptying the list took every display's switch away, the one just pressed with them, and Home's
    // sliders on waking, until the scan answered. An older scan or write still loses its result to the new generation
    function _rescan(): void {
        root._generation++
        root._lastScan = 0
        root._scanError = ""
        root._settleRetried = false
        _settleRetry.stop()
        Qt.callLater(root.refresh, true)
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
    // a write error outlives the rescans, so a retry asks again from a clean slate; the next failed write sets it back
    function retry(): void {
        root._writeError = ""
        root.refresh(true)
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
        root._settleRetried = false
        _settleRetry.stop()
        // running commands still verify their captured EDID; no later queued write survives
        Qt.callLater(root.refresh, true)
    }
    // deferred like invalidate() and _rescan(): a start or a wake sets off both, and Qt.callLater runs one refresh for
    // the two, where a scan begun here predated their new generation and every display was read twice
    on_WantedChanged: if (root._wanted) Qt.callLater(root.refresh, root._refreshPending)
    on_MenuWantedChanged: if (root._menuWanted && ShellSettings.barShowBrightness && !_scan.running)
        root.refresh(false)
    onAvailableChanged: root.invalidate()
    Connections {
        target: Quickshell
        function onScreensChanged() { root.invalidate() }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) return
            root._writeError = ""
            root._rescan()
        }
    }
    function levelFor(key: string): real { return Number(root.values[key] ?? 50) }
    // a wheel notch lands on the 5% grid, as the backlight's does, so a display that started off it lines up after one
    function notchPercent(current: int, delta: int): int {
        const notches = Math.round(delta / 5)
        if (notches === 0) return Math.max(1, Math.min(100, current + delta))
        const base = notches > 0 ? Math.floor(current / 5) : Math.ceil(current / 5)
        return Math.max(1, Math.min(100, (base + notches) * 5))
    }
    function bumpAllBy(delta: int, backlight: string): void {
        if (!root.available || delta === 0) return
        for (const display of root.controllableDisplays) {
            // a selected kernel DDC backlight already moves this I2C bus
            if (backlight === "ddcci" + display.bus) continue
            const current = Math.round(root.levelFor(display.key))
            const next = root.notchPercent(current, delta)
            if (next !== current) root.setPercent(display.key, next)
        }
    }
    function setPercent(key: string, percent: real): void {
        if (!root.available || !isFinite(percent)
                || Quickshell.env("SILERE_SANDBOX") === "1") return
        if (!root.controllableDisplays.some(d => d.key === key)) return
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
        const display = root.controllableDisplays.find(d => d.key === key)
        if (!display) { Qt.callLater(root._applyNext); return }
        root._writingKey = key
        root._writeGeneration = root._generation
        _write.command = ["bash", Quickshell.shellDir + "/scripts/display-brightness.sh", "write",
            display.connector, display.bus, display.identity, String(percent), String(display.maximum)]
        _write.running = true
    }
    function _resume(): void {
        if (root._refreshPending) root.refresh(true)
        root._applyNext()
    }

    function _acceptScanResult(generation: int, code: int, timedOut: bool, raw: string): void {
        if (generation !== root._generation) {
            root._refreshPending = true
            return
        }
        const complete = code === 0 && !timedOut
        const found = root.parseDisplays(raw, Quickshell.screens)
        // a monitor still waking from sleep, or just plugged in, can miss its first DDC read: that answer waits for one
        // more a few seconds on. What showed stays, an empty list takes the displays that answered, and no warning yet
        if (complete) {
            root._settleRetried = false
        } else if (!root._settleRetried) {
            root._settleRetried = true
            _settleRetry.restart()
            if (root.displays.length === 0) {
                root.displays = found.filter(d => !d.unreadable)
                const provisional = {}
                for (const display of root.displays)
                    provisional[display.key] = root._queued[display.key] ?? display.percent
                root.values = provisional
            }
            return
        }
        // each row is a completed read of one display. A slow or hung monitor
        // later in the scan must not discard the controls already discovered
        if (complete || found.length > 0) {
            root.displays = found
            const levels = {}
            for (const display of found)
                levels[display.key] = root._queued[display.key] ?? display.percent
            root.values = levels
        }
        const silent = found.filter(d => d.unreadable && !root.disabled(d.key)).map(d => d.label)
        root._scanError = complete ? "" : silent.length > 0
            ? silent.join(", ") + (silent.length === 1 ? " does" : " do")
                + " not answer DDC/CI. Switch off its control under Devices if it has none."
            : found.length > 0
            ? "Some external displays could not be read. Showing available brightness controls."
            : "Could not read external displays. Check DDC/CI support and I2C permissions."
        root._lastScan = complete ? Date.now() : 0
    }

    Timer { id: _debounce; interval: 100; onTriggered: root._applyNext() }
    Timer { id: _settleRetry; interval: 3000; onTriggered: root.refresh(true) }
    BoundedProcess {
        id: _scan
        timeoutMs: 20000
        command: ["bash", Quickshell.shellDir + "/scripts/display-brightness.sh", "list", ShellSettings.ddcDisabledDisplays]
        stdout: StdioCollector { id: _scanOut }
        onExited: code => {
            root._acceptScanResult(root._scanGeneration, code, _scan.timedOut, _scanOut.text)
            Qt.callLater(root._resume)
        }
    }
    BoundedProcess {
        id: _write
        // an unlinked connector needs a bounded detection before the write
        timeoutMs: 14000
        onExited: code => {
            root._writingKey = ""
            if (root._writeGeneration !== root._generation) {
                root._refreshPending = true
            } else if (!_write.completedSuccessfully(code)) {
                root._writeError = "Display brightness could not be changed."
                // the job already left the queue when it started; any value queued now belongs to a later adjustment
                root._lastScan = 0
                root._refreshPending = true
            } else {
                root._writeError = ""
            }
            // a partial scan also parks _lastScan at 0, for the Interface page's retry; a write that
            // worked on one of its displays must not rescan every display it could not read
            Qt.callLater(root._resume)
        }
    }
}
