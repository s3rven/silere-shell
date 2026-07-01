pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled:        false
    property bool _stopping:      false
    property bool _pendingEnable: false
    readonly property bool toolAvailable: SystemTools.hasHyprsunset
    readonly property int  temperature: ShellSettings.nightLightTemp

    // Location from the system timezone's zoneinfo coords (offline, no GPS); falls
    // back to a default latitude + tz offset if the lookup fails.
    property bool _geoResolved: false
    property real _autoLat: 0
    property real _autoLon: 0
    readonly property real _useLat: _geoResolved ? _autoLat : 45.0
    readonly property real _useLon: _geoResolved ? _autoLon
                                                 : -(new Date().getTimezoneOffset()) / 4  // tz minutes-west → degrees-east
    readonly property string locationLabel:
        Math.abs(_useLat).toFixed(0) + "°" + (_useLat >= 0 ? "N" : "S")

    property int _solarTick: 0
    // solar declination (radians); ticked so it tracks the date
    readonly property real _declRad: {
        root._solarTick
        const d = new Date()
        const n = Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 86400000)
        return 23.44 * Math.sin(2 * Math.PI * (n - 81) / 365) * Math.PI / 180
    }
    // Current solar elevation in degrees (shared by the temp curve + recommendation).
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
        return Math.round((3000 + 3500 * (elev + 6) / 12) / 100) * 100
    }

    readonly property real _solarNoon: {             // local clock hour the sun peaks
        root._solarTick
        return 12 - root._useLon / 15 - (new Date()).getTimezoneOffset() / 60
    }
    readonly property real _halfDay: {               // hours noon→sunset; 0 = polar night
        const c = Math.max(-1, Math.min(1, -Math.tan(root._useLat * Math.PI / 180) * Math.tan(root._declRad)))
        return Math.acos(c) * 180 / Math.PI / 15
    }
    readonly property real sunriseHour: _solarNoon - _halfDay
    readonly property real sunsetHour:  _solarNoon + _halfDay
    readonly property real _nowHour: { root._solarTick; const d = new Date(); return d.getHours() + d.getMinutes() / 60 }
    readonly property bool isDaytime: _halfDay > 0 && _nowHour >= sunriseHour && _nowHour <= sunsetHour
    // 0 at sunrise → 1 at sunset; -1 when the sun never rises today.
    readonly property real dayProgress:
        _halfDay <= 0 ? -1 : Math.max(0, Math.min(1, (_nowHour - sunriseHour) / (sunsetHour - sunriseHour)))
    // 0 at sunset → 0.5 at solar midnight → 1 at next sunrise; 0 for polar night.
    readonly property real nightProgress: {
        if (_halfDay <= 0) return 0
        const nightDur = 24 - (sunsetHour - sunriseHour)
        if (nightDur <= 0) return 0
        const afterSunset = (_nowHour - sunsetHour + 24) % 24
        return Math.max(0, Math.min(1, afterSunset / nightDur))
    }

    function _fmtHour(h: real): string {
        if (!isFinite(h)) return "--:--"
        let hh = Math.floor(((h % 24) + 24) % 24)
        let mm = Math.round((h - Math.floor(h)) * 60)
        if (mm >= 60) { mm -= 60; hh = (hh + 1) % 24 }
        return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
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

    // Recommend from sunset on; hint the turn-on time as the sun gets low. No midday nag.
    readonly property bool recommended: _elevation < 0
    readonly property string recommendLabel: {
        if (_halfDay >= 12)  return ""                       // sun never sets today
        if (recommended)     return "recommended"
        if (_elevation < 12) return "from " + sunsetLabel
        return ""
    }

    // ISO 6709 "±DDMM±DDDMM" (seconds optional) → decimal degrees.
    function _parseCoord(s: string): void {
        const m = /^([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$/.exec((s || "").trim())
        if (!m) return
        const latSign = m[1].charAt(0) === "-" ? -1 : 1
        const lonSign = m[4].charAt(0) === "-" ? -1 : 1
        root._autoLat = latSign * (Math.abs(Number(m[1])) + Number(m[2]) / 60 + (m[3] ? Number(m[3]) : 0) / 3600)
        root._autoLon = lonSign * (Math.abs(Number(m[4])) + Number(m[5]) / 60 + (m[6] ? Number(m[6]) : 0) / 3600)
        root._geoResolved = true
    }

    Process {
        id: _geoProc
        running: false
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

    // per-minute tick while auto is tracking the sun; single fresh tick on menu open
    Timer {
        interval: 60000; repeat: true
        running: root.toolAvailable && ShellSettings.nightLightAuto
        onTriggered: root._solarTick++
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._solarTick++ }
    }

    onSuggestedTempChanged: {
        if (ShellSettings.nightLightAuto && root.enabled) ShellSettings.nightLightTemp = root.suggestedTemp
    }
    Connections {
        target: ShellSettings
        function onNightLightAutoChanged() {
            if (ShellSettings.nightLightAuto && root.enabled) ShellSettings.nightLightTemp = root.suggestedTemp
        }
    }

    function _startSunset(): void {
        _sunsetProc.command = ["hyprsunset", "-t", String(temperature)]
        _sunsetProc.running = true
        enabled = true
    }

    onTemperatureChanged: {
        if (!root.enabled || !root.toolAvailable) return
        _pendingEnable = true
        if (_sunsetProc.running || _stopping) {
            _stopping = true
            if (_sunsetProc.running) _sunsetProc.running = false
        } else if (SystemTools.hasPkill && !_killProc.running) {
            _killProc.exec(["pkill", "-x", "hyprsunset"])
        } else if (!_killProc.running) {
            _pendingEnable = false
        }
        // If _killProc is already running, _pendingEnable is set; its
        // onExited handler will call _startSunset() with the new temperature.
    }

    function toggle(): void {
        if (!toolAvailable) return
        if (enabled) {
            _pendingEnable = false
            if (_killProc.running) { enabled = false; return }
            // Kill only the process we spawned; fall back to pkill only if we
            // didn't start it (i.e. it was already running when the shell launched).
            if (_sunsetProc.running || _stopping) {
                _stopping = true
                if (_sunsetProc.running) _sunsetProc.running = false
            } else if (SystemTools.hasPkill) {
                _killProc.exec(["pkill", "-x", "hyprsunset"])
            } else {
                return
            }
            enabled = false
        } else {
            if (_sunsetProc.running || _stopping) { _pendingEnable = true; return }
            // Don't spawn while a fallback pkill is still in flight, it matches
            // hyprsunset by name and would take the new instance down with it.
            // Queue the enable instead so the click isn't silently dropped.
            if (_killProc.running) { _pendingEnable = true; return }
            if (ShellSettings.nightLightAuto) ShellSettings.nightLightTemp = root.suggestedTemp
            _startSunset()
        }
    }

    Component.onCompleted: { _init(); _startGeo() }

    // Geo probe (timedatectl + zoneinfo lookup) only matters for auto-tracking,
    // which needs hyprsunset — don't spawn it when night light can't run. Guarded
    // one-shot so it still fires if toolAvailable only resolves once SystemTools
    // settles (called again from onReadyChanged).
    property bool _geoStarted: false
    function _startGeo(): void {
        if (_geoStarted || !toolAvailable) return
        _geoStarted = true
        _geoProc.running = true
    }

    function _init(): void {
        if (!SystemTools.ready) return
        if (!toolAvailable) { enabled = false; return }
        if (!SystemTools.hasPgrep) { enabled = _sunsetProc.running; return }
        if (!_sunsetProc.running) enabled = false
        if (!_checkProc.running) _checkProc.exec(["pgrep", "-x", "hyprsunset"])
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._init(); root._startGeo() }
    }

    Process {
        id: _checkProc
        stdout: SplitParser { onRead: root.enabled = true }
    }

    Process {
        id: _sunsetProc
        running: false
        onExited: {
            if (root._stopping) {
                root._stopping = false
                if (root._pendingEnable) {
                    root._pendingEnable = false
                    root._startSunset()
                }
                return
            }
            if (root.enabled) root.enabled = false
        }
    }

    Process {
        id: _killProc
        onExited: {
            if (root._pendingEnable) {
                root._pendingEnable = false
                root._startSunset()
            }
        }
    }
}
