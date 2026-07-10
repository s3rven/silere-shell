pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property real temp: 0
    readonly property bool available: temp > 0
    property bool _started: false
    readonly property bool needed: MenuState.open && MenuState.activeTab === 0
    readonly property bool _persistentNeed: ShellSettings.osdTempWarn
        || (ShellSettings.underlineGlow && ShellSettings.underlineTempGlow)
    readonly property bool _wanted: _started && (_persistentNeed || needed) && !Idle.isIdle
    property string _sensorPath: ""
    property bool _reading: false

    property int _hotCount:      0
    property int _criticalCount: 0
    // require N consecutive reads before alerting, ignores brief boost spikes
    readonly property int _enterSamples: 3

    // separate enter/exit thresholds to avoid flicker near the boundary
    property bool hot:      false
    property bool critical: false

    // warmup guard, qs hot-reload spikes cpu, suppress alerts until settled
    property bool _warmedUp: false
    Timer { id: _warmup; interval: 6000; onTriggered: root._warmedUp = true }

    readonly property int pulseDuration: critical ? Motion.ms(650) : Motion.ms(2000)
    property real alertPulse: 0

    PulseLoop {
        target:         root
        targetProperty: "alertPulse"
        duration:       root.pulseDuration
        // alertPulse only feeds menu gauges (bar underline glows off hot/critical, not the pulse); skip the 60fps loop while menu's closed
        running:        root.hot && !ShellSettings.reduceMotion && root.needed && !Idle.isIdle
    }

    // called per read, not onTempChanged — identical consecutive readings must still advance the counters
    function _sample(t: real): void {
        temp = t
        const hotEnter      = ShellSettings.tempHotThreshold
        const hotExit       = hotEnter - 5
        const criticalEnter = hotEnter + 8
        const criticalExit  = hotEnter + 5

        if (hot) {
            if (temp < hotExit) { hot = false; _hotCount = 0 }
        } else if (_warmedUp) {
            if (temp >= hotEnter) { _hotCount++; if (_hotCount >= root._enterSamples) hot = true }
            else                    _hotCount = 0
        }

        if (critical) {
            if (temp < criticalExit) { critical = false; _criticalCount = 0 }
        } else if (_warmedUp) {
            if (temp >= criticalEnter) { _criticalCount++; if (_criticalCount >= root._enterSamples) critical = true }
            else                         _criticalCount = 0
        }
    }

    function _normalizedTemp(raw: real): real {
        if (isNaN(raw) || raw <= 0) return 0
        const t = raw >= 1000 ? raw / 1000 : raw
        // ignore impossible values so a bogus fallback sensor can't trigger alerts
        return (t >= 5 && t <= 125) ? t : 0
    }

    function _resetState(): void {
        root.temp = 0
        root._hotCount = 0
        root._criticalCount = 0
        root.hot = false
        root.critical = false
    }

    on_WantedChanged: {
        if (!root._wanted) {
            _warmup.stop()
            if (_detectProc.running) _detectProc.running = false
            root._resetState()
            return
        }
        root._warmedUp = false
        _warmup.restart()
        if (root._sensorPath.length === 0 && !_detectProc.running)
            _detectProc.running = true
    }

    Component.onCompleted: root._started = true

    Process {
        id: _detectProc
        environment: ({ "LC_ALL": "C" })
        command: ["bash", "-c",
            "detect_sensor() { " +
            "  local best=\"\" best_score=0 name n dir f lf lbl score type tf; " +
            "  for name in /sys/class/hwmon/hwmon*/name; do " +
            "    [ -r \"$name\" ] || continue; " +
            "    n=$(cat \"$name\" 2>/dev/null); " +
            "    dir=${name%/name}; " +
            "    for f in \"$dir\"/temp*_input; do " +
            "      [ -r \"$f\" ] || continue; " +
            "      lf=\"${f%_input}_label\"; lbl=\"\"; " +
            "      [ -r \"$lf\" ] && lbl=$(cat \"$lf\" 2>/dev/null); " +
            "      score=0; key=\"${n,,}:${lbl,,}\"; " +
            "      case \"$key\" in " +
            "        k10temp:*tdie*|zenpower:*tdie*|coretemp:*package*|coretemp:*physical*) score=100 ;; " +
            "        k10temp:*tctl*|zenpower:*tctl*) score=90 ;; " +
            "        k10temp:*package*|zenpower:*package*) score=85 ;; " +
            "        k10temp:*tccd0*|zenpower:*tccd0*) score=75 ;; " +
            "        coretemp:*core*) score=60 ;; " +
            "        cpu_thermal:*|cpu-thermal:*|soc_thermal:*|bcm2835_thermal:*) score=55 ;; " +
            "        *:*cpu*|*:*package*|*:*physical*|*:*tctl*|*:*tdie*) score=50 ;; " +
            "        acpitz:*) score=15 ;; " +
            "      esac; " +
            "      if [ \"$score\" -gt \"$best_score\" ]; then best_score=\"$score\"; best=\"$f\"; fi; " +
            "    done; " +
            "  done; " +
            "  for tf in /sys/class/thermal/thermal_zone*/temp; do " +
            "    [ -r \"$tf\" ] || continue; " +
            "    type=\"\"; [ -r \"${tf%/temp}/type\" ] && type=$(cat \"${tf%/temp}/type\" 2>/dev/null); " +
            "    case \"${type,,}\" in " +
            "      x86_pkg_temp|cpu_thermal|cpu-thermal|soc_thermal|bcm2835_thermal) score=50 ;; " +
            "      acpitz) score=10 ;; " +
            "      *) score=0 ;; " +
            "    esac; " +
            "    if [ \"$score\" -gt \"$best_score\" ]; then best_score=\"$score\"; best=\"$tf\"; fi; " +
            "  done; " +
            "  [ -n \"$best\" ] || return 3; printf '%s\\n' \"$best\"; " +
            "}; " +
            "detect_sensor"]
        stdout: StdioCollector { id: _detectOut }
        onExited: (code) => {
            if (!root._wanted) return
            const path = code === 0 ? (_detectOut.text || "").trim() : ""
            root._sensorPath = path.startsWith("/sys/") ? path : ""
        }
        Component.onDestruction: running = false
    }

    FileView {
        id: _sensorFile
        path: root._sensorPath
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    function _readSensor(): void {
        if (!root._wanted || root._sensorPath.length === 0 || root._reading) return
        root._reading = true
        try {
            _sensorFile.reload()
            if (!_sensorFile.waitForJob()) {
                root._sensorPath = ""
                if (!_detectProc.running) _detectProc.running = true
                return
            }
            const t = root._normalizedTemp(parseFloat((_sensorFile.text() || "").trim()))
            if (t > 0) root._sample(t)
        } finally {
            root._reading = false
        }
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root._wanted && root._sensorPath.length > 0
        onTriggered: root._readSensor()
    }
}
