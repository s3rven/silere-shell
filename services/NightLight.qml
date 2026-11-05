pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "TimeZonePlace.js" as TimeZonePlace

Singleton {
    id: root

    readonly property bool armed: true

    property bool enabled:        false
    property string lastError:    ""
    property bool _stopping:      false
    property bool _pendingEnable: false
    property int _stateGeneration: 0
    property bool _probeFailed:   false
    // the gamma tool is whichever one the compositor can drive; the process this instance actually launched is what a stop has to name, not the current pick
    readonly property string tool: Settings.nightLightTool
    property string _runningTool: ""
    readonly property string _killTarget: _runningTool.length > 0 ? _runningTool : tool
    readonly property bool toolAvailable: tool.length > 0
    // a test shell on the same desktop stays hands off anyway; scripts/session.sh keeps any other session's tool safe
    readonly property bool _sandboxed: Quickshell.env("SILERE_SANDBOX") === "1"
    // auto is a mode, not a value: nightLightTemp stays whatever the user last chose by hand,
    // so turning auto off restores it instead of leaving the last solar step behind
    readonly property int  temperature: ShellSettings.nightLightAuto ? root.suggestedTemp
                                                                     : ShellSettings.nightLightTemp

    property bool _geoResolved: false
    property real _autoLat: 0
    property real _autoLon: 0
    readonly property real _useLat: _geoResolved ? _autoLat : 45.0
    readonly property real _useLon: _geoResolved ? _autoLon : root.standardOffsetLon(new Date().getFullYear())
    // summer time moves the clock, not the sun: guess the longitude from the standard offset, the later of january's and july's
    function standardOffsetLon(year: int): real {
        return -Math.max(new Date(year, 0, 1).getTimezoneOffset(), new Date(year, 6, 1).getTimezoneOffset()) / 4
    }
    readonly property string locationLabel:
        Math.abs(_useLat).toFixed(0) + "°" + (_useLat >= 0 ? "N" : "S")

    property int _solarTick: 0
    // noaa's fractional-year series: declination in radians and the equation of time in minutes
    readonly property real _yearAngle: {
        void root._solarTick
        const d = new Date()
        // counted in utc: a local-midnight difference is an hour short across a dst change
        const n = Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())
            - Date.UTC(d.getFullYear(), 0, 0)) / 86400000)
        return 2 * Math.PI / 365 * (n - 1 + (d.getHours() + d.getMinutes() / 60 - 12) / 24)
    }
    readonly property real _declRad: {
        const g = root._yearAngle
        return 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g)
            - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g)
            - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)
    }
    readonly property real _eqTimeMin: {
        const g = root._yearAngle
        return 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
            - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g))
    }
    readonly property real _elevation: {
        void root._solarTick
        const d    = new Date()
        const decl = root._declRad
        const h    = ((d.getUTCHours() + d.getUTCMinutes() / 60 + root._useLon / 15
            + root._eqTimeMin / 60 - 12) * 15) * Math.PI / 180
        const phi  = root._useLat * Math.PI / 180
        return Math.asin(Math.sin(phi) * Math.sin(decl) +
                         Math.cos(phi) * Math.cos(decl) * Math.cos(h)) * 180 / Math.PI
    }
    readonly property int suggestedTemp: {
        const elev = root._elevation
        if (elev >= 6)  return 6500
        if (elev <= -6) return 3000
        // wlsunset restarts on every step, so dusk takes a handful of steps rather than dozens
        return Math.round((3000 + 3500 * (elev + 6) / 12) / 500) * 500
    }

    readonly property real _solarNoon: {
        void root._solarTick
        return 12 - root._useLon / 15 - root._eqTimeMin / 60 - (new Date()).getTimezoneOffset() / 60
    }
    // -0.833°: refraction plus the sun's radius, so the times match published ones
    readonly property real _halfDay: {
        const phi = root._useLat * Math.PI / 180
        const decl = root._declRad
        const c = Math.max(-1, Math.min(1, Math.cos(90.833 * Math.PI / 180) / (Math.cos(phi) * Math.cos(decl))
            - Math.tan(phi) * Math.tan(decl)))
        return Math.acos(c) * 180 / Math.PI / 15
    }
    readonly property real sunriseHour: _solarNoon - _halfDay
    readonly property real sunsetHour:  _solarNoon + _halfDay
    readonly property real nowHour: { void root._solarTick; const d = new Date(); return d.getHours() + d.getMinutes() / 60 }
    // a midnight sun's day wraps past 24:00, which the window below cannot express
    readonly property bool isDaytime: _halfDay >= 12
        || (_halfDay > 0 && nowHour >= sunriseHour && nowHour <= sunsetHour)
    function _fmtHour(h: real): string {
        return isFinite(h) ? DateTime.hourText(h) : "--:--"
    }
    readonly property string sunriseLabel: _halfDay <= 0 ? "--:--" : _fmtHour(sunriseHour)
    readonly property string sunsetLabel:  _halfDay <= 0 ? "--:--" : _fmtHour(sunsetHour)

    function _dur(mins: real): string {
        const m = Math.max(0, Math.round(mins))
        const hh = Math.floor(m / 60), mm = m % 60
        return hh > 0 ? (hh + "h " + (mm < 10 ? "0" : "") + mm + "m") : (mm + "m")
    }
    readonly property string phaseLabel: {
        void root._solarTick
        if (_halfDay <= 0)  return "polar night"
        if (_halfDay >= 12) return "midnight sun"
        if (isDaytime)            return _dur((sunsetHour - nowHour) * 60) + " of daylight"
        if (nowHour < sunriseHour) return "sunrise in " + _dur((sunriseHour - nowHour) * 60)
        return "sunrise in " + _dur((24 - nowHour + sunriseHour) * 60)
    }

    // sentence case like the row's other statuses; phaseLabel is a caption inside the arc and stays lowercase
    readonly property string offStatus: root.offStatusAt(nowHour, _elevation)
    function offStatusAt(hour: real, elevation: real): string {
        if (_halfDay <= 0 || _halfDay >= 12) return ""
        if (hour < sunriseHour || hour > sunsetHour) return "Sunrise " + sunriseLabel
        if (hour >= _solarNoon && elevation < 12) return "Sunset " + sunsetLabel
        return ""
    }

    function _parseCoord(s: string): bool {
        const c = TimeZonePlace.parseCoord(s)
        if (!c) return false
        root._autoLat = c.lat
        root._autoLon = c.lon
        root._geoResolved = true
        return true
    }

    BoundedProcess {
        id: _geoProc
        running: false
        timeoutMs: 5000
        command: ["bash", "-c", TimeZonePlace.script]
        stdout: StdioCollector { id: _geoOut }
        onExited: code => {
            if (!_geoProc.completedSuccessfully(code)
                    || !root._parseCoord(String(_geoOut.text).split("\t")[0]))
                root._geoStarted = false
        }
    }

    Timer {
        interval: 60000; repeat: true
        // the menu draws the sun's position too, so it keeps moving while open
        running: root.toolAvailable && !Idle.isIdle
            && ((ShellSettings.nightLightAuto && root.enabled) || MenuState.open)
        onTriggered: root._solarTick++
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._solarTick++ }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle && ShellSettings.nightLightAuto && root.enabled) root._solarTick++
        }
    }
    // the minute timer stops across suspend; the network returning is the wake the shell sees
    Connections {
        target: Network
        function onConnectedChanged() {
            if (ShellSettings.nightLightAuto && root.enabled) root._solarTick++
        }
    }

    Connections {
        target: ShellSettings
        function onNightLightAutoChanged() {
            if (ShellSettings.nightLightAuto && root.enabled) root._solarTick++
        }
    }

    function _startSunset(): void {
        const argv = Settings.nightLightCommand(root.temperature)
        if (argv.length === 0) { root.enabled = false; return }
        root.lastError = ""
        root._probeFailed = false
        root._runningTool = root.tool
        _sunsetProc._lastErrLine = ""
        _sunsetProc.command = argv
        _sunsetProc.running = true
        enabled = true
    }

    // hyprsunset takes a new temperature over hyprctl; a restart per step blinks the gamma off
    function _setTemperature(): void {
        if (!root.enabled || !root.toolAvailable) return
        if (root._runningTool !== "hyprsunset" || !SystemTools.hasHyprctl
                || root._stopping || _killProc.running) {
            root._restart()
            return
        }
        if (!_tempProc.running) root._sendTemperature()
    }

    function _sendTemperature(): void {
        if (_tempProc.running) return
        _tempProc._targetTemp = root.temperature
        _tempProc._generation = root._stateGeneration
        _tempProc.exec(Settings.hyprsunsetNeutral(_tempProc._targetTemp)
            ? ["hyprctl", "hyprsunset", "identity"]
            : ["hyprctl", "hyprsunset", "temperature", String(_tempProc._targetTemp)])
    }

    function _temperatureUpdateSucceeded(code: int, timedOut: bool, response: string): bool {
        return !timedOut && code === 0 && (response || "").trim().toLowerCase() === "ok"
    }

    Timer {
        id: _queuedTemp
        interval: 0
        onTriggered: {
            if (root.enabled && !root._stopping
                    && root._runningTool === "hyprsunset" && root.tool === "hyprsunset")
                root._sendTemperature()
        }
    }

    BoundedProcess {
        id: _tempProc
        property int _targetTemp: 0
        property int _generation: -1
        timeoutMs: 3000
        stdout: StdioCollector { id: _tempOut }
        onExited: (code) => {
            if (_tempProc._generation !== root._stateGeneration) {
                if (root.enabled && !root._stopping
                        && root._runningTool === "hyprsunset" && root.tool === "hyprsunset")
                    _queuedTemp.restart()
                return
            }
            if (!root.enabled || root._stopping
                    || root._runningTool !== "hyprsunset" || root.tool !== "hyprsunset") return
            if (root.temperature !== _tempProc._targetTemp) {
                _queuedTemp.restart()
                return
            }
            if (!root._temperatureUpdateSucceeded(code, _tempProc.timedOut, _tempOut.text))
                root._restart()
        }
    }

    // wlsunset has no live temperature command, and a failed hyprctl update falls back to this
    function _restart(): void {
        if (!root.enabled || !root.toolAvailable) return
        _pendingEnable = true
        if (_sunsetProc.running || _stopping) {
            _stopping = true
            if (_sunsetProc.running) _sunsetProc.running = false
        } else if (SystemTools.hasPgrep && !_killProc.running) {
            root._stopSessionTool()
        } else if (!_killProc.running) {
            _pendingEnable = false
            root.lastError = "Install pgrep to change an external night light"
        }
    }

    function _stopSessionTool(): void {
        _killProc.exec(["bash", Quickshell.shellDir + "/scripts/session.sh", "tool-stop", root._killTarget])
    }

    onTemperatureChanged: root._setTemperature()

    onToolChanged: {
        root._stateGeneration++
        if (!root.enabled) { root._runningTool = ""; return }
        if (!root.toolAvailable) { root._syncToolAvailability(); return }
        if (root._runningTool.length > 0 && root._runningTool !== root.tool)
            root._restart()
    }

    function toggle(): void {
        if (!toolAvailable || _sandboxed) return
        // any pgrep in flight describes the state before this action
        root._stateGeneration++
        root._restoreDone = true
        ShellSettings.nightLightOn = !enabled
        if (enabled) {
            _pendingEnable = false
            if (_killProc.running) { enabled = false; return }
            if (_sunsetProc.running || _stopping) {
                _stopping = true
                if (_sunsetProc.running) _sunsetProc.running = false
            } else if (SystemTools.hasPgrep) {
                root._stopSessionTool()
            } else {
                root.lastError = "Install pgrep to stop an external night light"
                return
            }
            enabled = false
        } else {
            if (_sunsetProc.running || _stopping) { _pendingEnable = true; return }
            // don't spawn while a stop is in flight — it matches hyprsunset by name and would kill the new instance; queue instead
            if (_killProc.running) { _pendingEnable = true; return }
            if (ShellSettings.nightLightAuto) root._solarTick++
            _startSunset()
        }
    }

    // the menu is what instantiates this singleton, so _startGeo's opening edge is already spent by first load
    Component.onCompleted: { _init(); _startGeo() }

    property bool _geoStarted: false
    readonly property bool _geoWanted: toolAvailable
        && (ShellSettings.nightLightAuto || ControlSurfaces.anyOpen)
    function _startGeo(): void {
        if (_geoStarted || !_geoWanted) return
        _geoStarted = true
        _geoProc.running = true
    }

    function _init(): void {
        if (_sandboxed || !SystemTools.ready) return
        if (!toolAvailable) { enabled = false; return }
        if (!SystemTools.hasPgrep) {
            enabled = _sunsetProc.running
            root._probedOnce = true
            root._maybeRestore()
            return
        }
        if (_killProc.running || root._stopping || root._pendingEnable) return
        // the tool this shell launched is known alive without scanning the process table on every menu open
        if (_sunsetProc.running) {
            root._probedOnce = true
            root._maybeRestore()
            return
        }
        if (!_checkProc.running) {
            _checkProc._generation = root._stateGeneration
            _checkProc.exec(["bash", Quickshell.shellDir + "/scripts/session.sh", "tool-find", root.tool])
        }
    }

    // -1 means the probe itself failed; otherwise answer the state without making an old no-match override the daemon this instance just started
    function _probeState(code: int, status: int, timedOut: bool, selfRunning: bool): int {
        if (timedOut || status !== 0 || (code !== 0 && code !== 1)) return -1
        return code === 0 || selfRunning ? 1 : 0
    }

    function _syncToolAvailability(): void {
        if (!SystemTools.ready) return
        root._stateGeneration++
        if (!root.toolAvailable) {
            root._pendingEnable = false
            root.enabled = false
            root.lastError = ""
            root._probeFailed = false
            if (_checkProc.running) _checkProc.running = false
            if (_killProc.running) _killProc.running = false
            if (_sunsetProc.running) {
                root._stopping = true
                _sunsetProc.running = false
            } else {
                root._stopping = false
            }
            return
        }
        root._init()
        root._startGeo()
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._syncToolAvailability() }
        function onScanRevisionChanged() { root._syncToolAvailability() }
    }
    Connections {
        target: ShellSettings
        function onNightLightAutoChanged() { root._startGeo() }
    }
    Connections {
        target: ControlSurfaces
        function onAnyOpenChanged() {
            if (ControlSurfaces.anyOpen) {
                root._init()
                root._startGeo()
            }
        }
    }

    BoundedProcess {
        id: _checkProc
        property int _generation: -1
        timeoutMs: 5000
        // pgrep's normal exit 1 means no match; a crash with signal 1 is a failed probe
        onExited: (code, status) => {
            if (_checkProc._generation !== root._stateGeneration) {
                if (root.toolAvailable) Qt.callLater(root._init)
                return
            }
            if (!root.toolAvailable) return
            const state = root._probeState(
                code, status, _checkProc.timedOut, _sunsetProc.running)
            if (state < 0) {
                root._probeFailed = true
                root.lastError = "could not check for a running " + root.tool
                return
            }
            if (root._probeFailed) {
                root._probeFailed = false
                root.lastError = ""
            }
            root.enabled = state === 1
            if (root.enabled && root._runningTool.length === 0)
                root._runningTool = root.tool
            root._probedOnce = true
            root._maybeRestore()
        }
    }

    // a restart kills the tool: bring back a hand-chosen state once, never a tool that died later
    property bool _probedOnce: false
    property bool _restoreDone: false
    function _maybeRestore(): void {
        if (root._restoreDone || !root._probedOnce || !ShellSettings.ready) return
        root._restoreDone = true
        if (!ShellSettings.nightLightOn || root.enabled || !root.toolAvailable) return
        if (_sunsetProc.running || root._stopping || _killProc.running) return
        if (ShellSettings.nightLightAuto) root._solarTick++
        root._startSunset()
    }
    Connections {
        target: ShellSettings
        function onReadyChanged() { root._maybeRestore() }
    }

    // bounded only for its exit report: a tool removed mid-session fails to start without one
    BoundedProcess {
        id: _sunsetProc
        running: false
        // a StdioCollector grows for as long as the night light runs; keep only the last line
        property string _lastErrLine: ""
        stderr: SplitParser {
            onRead: line => {
                const trimmed = line.trim()
                if (trimmed.length > 0) _sunsetProc._lastErrLine = SafeText.singleLineText(trimmed)
            }
        }
        onExited: (code, status) => {
            const stopped = root._runningTool.length > 0
                ? root._runningTool : "The night light"
            if (root._stopping) {
                root._stopping = false
                root._runningTool = ""
                if (root._pendingEnable) {
                    root._pendingEnable = false
                    root._startSunset()
                }
                return
            }
            // not a deliberate stop, and enabled was set optimistically at launch, so
            // without this the toggle just flips back unexplained. status 0 is
            // QProcess.NormalExit; a tool killed from outside reports a signal in code,
            // and wlsunset's running commentary on stderr is not the reason it went away
            if (code !== 0)
                root.lastError = status === 0
                    ? (_sunsetProc._lastErrLine.length > 0 ? _sunsetProc._lastErrLine
                        : code === 127 ? stopped + " could not start"
                        : stopped + " stopped unexpectedly")
                    : (stopped + " stopped unexpectedly")
            root._runningTool = ""
            if (root.enabled) root.enabled = false
        }
    }

    function _acceptStopResult(code: int, status: int, timedOut: bool): void {
        if (!root.toolAvailable) {
            root._pendingEnable = false
            root.lastError = ""
            return
        }
        // only a normal exit with 0 or 1 confirms the stop. A missing helper
        // reports 127, and a crash can share its signal number with "no match"
        if (timedOut || status !== 0 || (code !== 0 && code !== 1)) {
            root._pendingEnable = false
            root.lastError = "Could not stop the external night light"
            root._init()
            return
        }
        root.lastError = ""
        root._runningTool = ""
        if (root._pendingEnable) {
            root._pendingEnable = false
            root._startSunset()
        }
    }

    BoundedProcess {
        id: _killProc
        timeoutMs: 5000
        onExited: (code, status) => root._acceptStopResult(code, status, _killProc.timedOut)
    }
}
