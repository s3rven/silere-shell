pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property real temp: 0
    property bool _started: false

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

    readonly property int pulseDuration: critical ? 650 : 2000
    property real alertPulse: 0

    PulseLoop {
        target:         root
        targetProperty: "alertPulse"
        duration:       root.pulseDuration
        // alertPulse is only consumed by the menu gauges (the bar underline glows off
        // hot/critical, not the pulse), so don't run the 60fps loop while menu's closed.
        running:        root.hot && !ShellSettings.reduceMotion && MenuState.open
    }

    // Called once per sensor read, not from onTempChanged: identical consecutive
    // readings (steady sensor pinned at threshold) must still advance the counters.
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

    Component.onCompleted: {
        root._started = true
        _warmup.restart()
    }

    SupervisedProcess {
        id: _proc
        superviseWhen: root._started && !Idle.isIdle
        restartDelay:  2000
        giveUpCodes:   [3]            // exit 3 = no usable temperature sensor
        command: ["bash", "-c",
            "detect_sensor() { " +
            "  local p=\"\" name n dir pkg first f lf lbl; " +
            "  for name in /sys/class/hwmon/hwmon*/name; do " +
            "    [ -r \"$name\" ] || continue; " +
            "    n=$(cat \"$name\" 2>/dev/null); " +
            "    case \"$n\" in k10temp|coretemp|zenpower|cpu_thermal|acpitz) " +
            "      dir=${name%/name}; pkg=\"\"; first=\"\"; " +
            "      for f in \"$dir\"/temp*_input; do " +
            "        [ -r \"$f\" ] || continue; " +
            "        lf=\"${f%_input}_label\"; lbl=\"\"; " +
            "        [ -r \"$lf\" ] && lbl=$(cat \"$lf\" 2>/dev/null); " +
            "        case \"$lbl\" in *Package*|*Tdie*|*Tccd0*) [ -z \"$pkg\" ] && pkg=\"$f\" ;; esac; " +
            "        [ -z \"$first\" ] && first=\"$f\"; " +
            "      done; " +
            "      p=\"${pkg:-$first}\"; [ -n \"$p\" ] && break; " +
            "    esac; " +
            "  done; " +
            "  [ -z \"$p\" ] && for f in /sys/class/thermal/thermal_zone*/temp; do " +
            "    [ -r \"$f\" ] && { p=\"$f\"; break; }; " +
            "  done; " +
            "  echo \"$p\"; " +
            "}; " +
            "p=$(detect_sensor); [ -z \"$p\" ] && exit 3; " +
            // fd 3 holds both ends of a pipe, so read -t sleeps the full
            // timeout without forking an external `sleep` every tick
            "exec 3<> <(:); " +
            "while true; do " +
            "  if [ -r \"$p\" ]; then read t < \"$p\" && echo \"$t\"; " +
            "  else p=$(detect_sensor); [ -z \"$p\" ] && exit 3; fi; " +
            "  read -r -t 5 -u 3; " +
            "done"]
        stdout: SplitParser {
            onRead: line => {
                const v = parseInt(line.trim())
                if (!isNaN(v) && v > 0) root._sample(v / 1000)
            }
        }
        onRunningChanged: {
            if (!running) {
                root.temp = 0; root._hotCount = 0; root._criticalCount = 0
                root.hot = false; root.critical = false
            } else {
                // Sensor (re)started, re-arm the warmup so a relaunch spike can't alert.
                root._warmedUp = false
                _warmup.restart()
            }
        }
    }
}
