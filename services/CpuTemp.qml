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
    readonly property bool needed: MenuState.homeActive
        || (MenuState.settingsActive
            && (MenuState.settingsSection === "warnings"
                || MenuState.settingsSection === "underline"))
    readonly property bool _persistentNeed: ShellSettings.osdTempWarn
        || (ShellSettings.underlineGlow && ShellSettings.underlineTempGlow)
    readonly property bool _wanted: _started && (_persistentNeed || needed) && !Idle.isIdle
    property string _sensorPath: ""
    property bool _reading: false
    property bool _probeComplete: false
    // available drops to false whenever the service is released, so a control
    // gated on it flickers on every menu open; sensors do not come and go
    readonly property bool sensorMissing: _probeComplete && _sensorPath.length === 0

    property int _hotCount:      0
    property int _criticalCount: 0
    readonly property int _enterSamples: 3

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
        active:         root.hot && root.needed && !Idle.isIdle
    }

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
        return (t >= 5 && t <= 125) ? t : 0
    }

    function _resetState(): void {
        root._reading = false
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
            if (root._sensorPath.length === 0) root._probeComplete = true
        }
        Component.onDestruction: running = false
    }

    FileView {
        id: _sensorFile
        path: root._sensorPath
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._finishSensorRead(_sensorFile.text())
        onLoadFailed: root._failSensorRead()
    }

    function _readSensor(): void {
        if (!root._wanted || root._sensorPath.length === 0 || root._reading) return
        root._reading = true
        _sensorFile.reload()
    }

    function _finishSensorRead(raw: string): void {
        if (!root._reading) return
        root._reading = false
        if (!root._wanted) return
        const t = root._normalizedTemp(parseFloat((raw || "").trim()))
        if (t > 0) root._sample(t)
        root._probeComplete = true
    }

    function _failSensorRead(): void {
        if (!root._reading) return
        root._reading = false
        if (!root._wanted) return
        root._probeComplete = false
        root._sensorPath = ""
        if (!_detectProc.running) _detectProc.running = true
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root._wanted && root._sensorPath.length > 0
        onTriggered: root._readSensor()
    }
}
