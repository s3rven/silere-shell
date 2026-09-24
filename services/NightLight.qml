pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property bool enabled:        false
    property string lastError:    ""
    property bool _stopping:      false
    property bool _pendingEnable: false
    property int _stateGeneration: 0
    property bool _probeFailed:   false
    // the gamma tool is whichever one the compositor can drive; the process this
    // instance actually launched is what a stop has to name, not the current pick
    readonly property string tool: Settings.nightLightTool
    property string _runningTool: ""
    readonly property string _killTarget: _runningTool.length > 0 ? _runningTool : tool
    readonly property bool toolAvailable: tool.length > 0
    // auto is a mode, not a value: nightLightTemp stays whatever the user last chose by hand,
    // so turning auto off restores it instead of leaving the last solar step behind
    readonly property int  temperature: ShellSettings.nightLightAuto ? root.suggestedTemp
                                                                     : ShellSettings.nightLightTemp

    property bool _geoResolved: false
    property real _autoLat: 0
    property real _autoLon: 0
    readonly property real _useLat: _geoResolved ? _autoLat : 45.0
    readonly property real _useLon: _geoResolved ? _autoLon
                                                 : -(new Date().getTimezoneOffset()) / 4
    readonly property string locationLabel:
        Math.abs(_useLat).toFixed(0) + "°" + (_useLat >= 0 ? "N" : "S")

    property int _solarTick: 0
    readonly property real _declRad: {
        root._solarTick
        const d = new Date()
        const n = Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 86400000)
        return 23.44 * Math.sin(2 * Math.PI * (n - 81) / 365) * Math.PI / 180
    }
    readonly property real _elevation: {
        root._solarTick
        const d    = new Date()
        const decl = root._declRad
        const h    = ((d.getUTCHours() + d.getUTCMinutes() / 60 + root._useLon / 15 - 12) * 15) * Math.PI / 180
        const phi  = root._useLat * Math.PI / 180
        return Math.asin(Math.sin(phi) * Math.sin(decl) +
                         Math.cos(phi) * Math.cos(decl) * Math.cos(h)) * 180 / Math.PI
    }
    readonly property int suggestedTemp: {
        const elev = root._elevation
        if (elev >= 6)  return 6500
        if (elev <= -6) return 3000
        // every step restarts the tool, so dusk takes a handful of steps rather than dozens
        return Math.round((3000 + 3500 * (elev + 6) / 12) / 500) * 500
    }

    readonly property real _solarNoon: {
        root._solarTick
        return 12 - root._useLon / 15 - (new Date()).getTimezoneOffset() / 60
    }
    readonly property real _halfDay: {
        const c = Math.max(-1, Math.min(1, -Math.tan(root._useLat * Math.PI / 180) * Math.tan(root._declRad)))
        return Math.acos(c) * 180 / Math.PI / 15
    }
    readonly property real sunriseHour: _solarNoon - _halfDay
    readonly property real sunsetHour:  _solarNoon + _halfDay
    readonly property real _nowHour: { root._solarTick; const d = new Date(); return d.getHours() + d.getMinutes() / 60 }
    // a midnight sun's day wraps past 24:00, which the window below cannot express
    readonly property bool isDaytime: _halfDay >= 12
        || (_halfDay > 0 && _nowHour >= sunriseHour && _nowHour <= sunsetHour)
    readonly property real dayProgress:
        _halfDay <= 0 ? -1 : Math.max(0, Math.min(1, (_nowHour - sunriseHour) / (sunsetHour - sunriseHour)))
    readonly property real nightProgress: {
        if (_halfDay <= 0) return 0
        const nightDur = 24 - (sunsetHour - sunriseHour)
        if (nightDur <= 0) return 0
        const afterSunset = (_nowHour - sunsetHour + 24) % 24
        return Math.max(0, Math.min(1, afterSunset / nightDur))
    }

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
        root._solarTick
        if (_halfDay <= 0)  return "polar night"
        if (_halfDay >= 12) return "midnight sun"
        if (isDaytime)            return _dur((sunsetHour - _nowHour) * 60) + " of daylight"
        if (_nowHour < sunriseHour) return "sunrise in " + _dur((sunriseHour - _nowHour) * 60)
        return "sunrise in " + _dur((24 - _nowHour + sunriseHour) * 60)
    }

    readonly property bool recommended: _elevation < 0
    readonly property string recommendLabel: {
        // this lands in the same row slot as "Not connected" and "Quiet hours", which are
        // sentence case; phaseLabel is a caption inside the arc and stays lowercase
        if (_halfDay >= 12)  return ""
        if (recommended)     return "Recommended"
        if (_elevation < 12) return "From " + sunsetLabel
        return ""
    }

    function _parseCoord(s: string): bool {
        const m = /^([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$/.exec((s || "").trim())
        if (!m) return false
        const latDeg = Math.abs(Number(m[1]))
        const latMin = Number(m[2])
        const latSec = m[3] ? Number(m[3]) : 0
        const lonDeg = Math.abs(Number(m[4]))
        const lonMin = Number(m[5])
        const lonSec = m[6] ? Number(m[6]) : 0
        if (latMin >= 60 || lonMin >= 60 || latSec >= 60 || lonSec >= 60
                || latDeg > 90 || lonDeg > 180
                || (latDeg === 90 && (latMin > 0 || latSec > 0))
                || (lonDeg === 180 && (lonMin > 0 || lonSec > 0))) return false
        const latSign = m[1].charAt(0) === "-" ? -1 : 1
        const lonSign = m[4].charAt(0) === "-" ? -1 : 1
        root._autoLat = latSign * (latDeg + latMin / 60 + latSec / 3600)
        root._autoLon = lonSign * (lonDeg + lonMin / 60 + lonSec / 3600)
        root._geoResolved = true
        return true
    }

    BoundedProcess {
        id: _geoProc
        running: false
        timeoutMs: 5000
        command: ["bash", "-c",
            "tz=\"$(timedatectl show -p Timezone --value 2>/dev/null)\"; " +
            "[ -z \"$tz\" ] && tz=\"$(readlink -f /etc/localtime 2>/dev/null | sed -n 's#.*/zoneinfo/##p')\"; " +
            "[ -z \"$tz\" ] && [ -r /etc/timezone ] && tz=\"$(cat /etc/timezone)\"; " +
            "[ -z \"$tz\" ] && exit 0; " +
            "for f in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do " +
            "  [ -r \"$f\" ] || continue; " +
            "  c=\"$(awk -v z=\"$tz\" 'BEGIN{FS=\"\\t\"} $0 !~ /^#/ && $3==z {print $2; exit}' \"$f\")\"; " +
            "  [ -n \"$c\" ] && { printf '%s\\n' \"$c\"; break; }; " +
            "done"]
        stdout: StdioCollector { id: _geoOut }
        onExited: root._parseCoord(_geoOut.text)
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

    // the tools take their temperature at launch, so a new value means a new process
    function _restart(): void {
        if (!root.enabled || !root.toolAvailable) return
        _pendingEnable = true
        if (_sunsetProc.running || _stopping) {
            _stopping = true
            if (_sunsetProc.running) _sunsetProc.running = false
        } else if (SystemTools.hasPkill && !_killProc.running) {
            _killProc.exec(["pkill", "-x", root._killTarget])
        } else if (!_killProc.running) {
            _pendingEnable = false
            root.lastError = "Install pkill to change an external night light"
        }
    }

    onTemperatureChanged: root._restart()

    onToolChanged: {
        root._stateGeneration++
        if (!root.enabled) { root._runningTool = ""; return }
        if (!root.toolAvailable) { root._syncToolAvailability(); return }
        if (root._runningTool.length > 0 && root._runningTool !== root.tool)
            root._restart()
    }

    function toggle(): void {
        if (!toolAvailable) return
        // any pgrep in flight describes the state before this action
        root._stateGeneration++
        if (enabled) {
            _pendingEnable = false
            if (_killProc.running) { enabled = false; return }
            if (_sunsetProc.running || _stopping) {
                _stopping = true
                if (_sunsetProc.running) _sunsetProc.running = false
            } else if (SystemTools.hasPkill) {
                _killProc.exec(["pkill", "-x", root._killTarget])
            } else {
                root.lastError = "Install pkill to stop an external night light"
                return
            }
            enabled = false
        } else {
            if (_sunsetProc.running || _stopping) { _pendingEnable = true; return }
            // don't spawn while a fallback pkill is in flight — it matches hyprsunset by name and would kill the new instance; queue instead
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
        if (!SystemTools.ready) return
        if (!toolAvailable) { enabled = false; return }
        if (!SystemTools.hasPgrep) { enabled = _sunsetProc.running; return }
        if (_killProc.running || root._stopping || root._pendingEnable) return
        if (!_checkProc.running) {
            _checkProc._generation = root._stateGeneration
            _checkProc.exec(["pgrep", "-x", root.tool])
        }
    }

    // -1 means the probe itself failed; otherwise answer the state without
    // making an old no-match override the daemon this instance just started.
    function _probeState(code: int, timedOut: bool, selfRunning: bool): int {
        if (timedOut || (code !== 0 && code !== 1)) return -1
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
        // pgrep answers "no match" with 1, so only 2+ or a timeout means the probe never ran
        onExited: (code) => {
            if (_checkProc._generation !== root._stateGeneration) {
                if (root.toolAvailable) Qt.callLater(root._init)
                return
            }
            if (!root.toolAvailable) return
            const state = root._probeState(
                code, _checkProc.timedOut, _sunsetProc.running)
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
        }
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

    BoundedProcess {
        id: _killProc
        timeoutMs: 5000
        onExited: (code) => {
            if (!root.toolAvailable) {
                root._pendingEnable = false
                root.lastError = ""
                return
            }
            // pkill exit 1 just means nothing matched — the common case when no
            // external tool is running. Only 2 (usage) and 3 (fatal) are real errors
            if (_killProc.timedOut || code === 2 || code === 3) {
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
    }
}
