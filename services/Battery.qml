pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../config"

Singleton {
    id: root

    readonly property bool upowerReady: UPower.displayDevice && UPower.displayDevice.ready
    readonly property bool available: upowerReady && UPower.displayDevice.isPresent
    // UPower reports 0-1 or 0-100 depending on setup; a value >1 latches the 0-100 scale
    readonly property real _raw: upowerReady ? UPower.displayDevice.percentage : 0
    property bool _scale100: false
    property real _pctOverride: -1
    property int  _ambiguousAttempts: 0
    Binding {
        target: root
        property: "_scale100"
        value: true
        when: root._raw > 1.0
        restoreMode: Binding.RestoreNone
    }
    readonly property bool _ambiguousRawOne: available && !_scale100 && Math.abs(_raw - 1) < 0.0001
    // the probe budget and its answer belong to one ambiguous spell: without this a reading that
    // leaves and re-enters ambiguity reuses a spent budget and the percentage the earlier spell resolved
    function _clearAmbiguityProbe(): void {
        root._ambiguousAttempts = 0
        root._pctOverride = -1
    }
    on_AmbiguousRawOneChanged: if (!root._ambiguousRawOne) root._clearAmbiguityProbe()

    function normalizedPercent(raw, percentScale: bool): real {
        const value = Number(raw)
        if (!isFinite(value) || value <= 0) return 0
        // a raw 64 paints as 6400% for a frame while the scale latch is still catching up
        const percent = percentScale || value > 1 ? value : value * 100
        return Math.max(0, Math.min(100, percent))
    }

    readonly property real pct: (_ambiguousRawOne && _pctOverride >= 0)
        ? _pctOverride
        : root.normalizedPercent(_raw, _scale100)
    readonly property bool onBattery: available ? UPower.onBattery : false
    readonly property int  _critPct: Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2))
    // pct==0 is UPower's uninitialised reading at startup; would fire a bogus critical alert
    readonly property bool _validReading: available && pct > 0
    readonly property bool low: _validReading && pct < ShellSettings.batteryLowThreshold && onBattery
    readonly property bool critical: _validReading && pct < _critPct && onBattery
    readonly property bool charging: available && !onBattery
    readonly property bool full:     available && pct >= 99
    readonly property int pulseDuration: critical ? Motion.ms(650) : Motion.ms(2000)
    property real alertPulse: 0

    readonly property color iconColor: {
        if (!available || !_validReading)             return Theme.subtext
        if (charging)                                 return full ? Theme.success : Theme.accent
        if (pct < _critPct)                           return Theme.error
        if (pct < ShellSettings.batteryLowThreshold)  return Theme.warning
        return Theme.accent
    }

    readonly property string icon: {
        if (!available || !_validReading)  return "󰂎"
        if (!onBattery) {
            if (pct >= 95)   return "󰂅"
            if (pct >= 90)   return "󰂋"
            if (pct >= 80)   return "󰂊"
            if (pct >= 70)   return "󰢞"
            if (pct >= 60)   return "󰂉"
            if (pct >= 50)   return "󰢝"
            if (pct >= 40)   return "󰂈"
            if (pct >= 30)   return "󰂇"
            if (pct >= 20)   return "󰂆"
            return "󰢜"
        }
        if (pct >= 95)   return "󰁹"
        if (pct >= 90)   return "󰂂"
        if (pct >= 80)   return "󰂁"
        if (pct >= 70)   return "󰂀"
        if (pct >= 60)   return "󰁿"
        if (pct >= 50)   return "󰁾"
        if (pct >= 40)   return "󰁽"
        if (pct >= 30)   return "󰁼"
        if (pct >= 20)   return "󰁻"
        return "󰁺"
    }

    readonly property string label: _validReading ? `${Math.round(pct)}%` : ""

    Timer {
        interval: 1500
        repeat: true
        running: root._ambiguousRawOne && root._pctOverride < 0
            && root._ambiguousAttempts < 3 && !_percentProbe.running
        onTriggered: {
            root._ambiguousAttempts++
            _percentProbe.running = true
        }
    }

    BoundedProcess {
        id: _percentProbe
        running: false
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        command: ["bash", "-c",
            "command -v upower >/dev/null 2>&1 || exit 0; " +
            "upower -i /org/freedesktop/UPower/devices/DisplayDevice 2>/dev/null " +
            "| awk -F: '/percentage/ { gsub(/[^0-9.]/, \"\", $2); print $2; exit }'"]
        stdout: StdioCollector { id: _percentProbeOut }
        onExited: {
            const n = Number((_percentProbeOut.text || "").trim())
            if (!isNaN(n) && n > 0 && n <= 100 && root._ambiguousRawOne)
                root._pctOverride = n
        }
    }

    readonly property real   timeToEmpty: upowerReady ? UPower.displayDevice.timeToEmpty : 0
    readonly property real   timeToFull:  upowerReady ? UPower.displayDevice.timeToFull  : 0
    readonly property string timeLabel: {
        const secs = onBattery ? timeToEmpty : timeToFull
        if (!available || secs <= 0) return ""
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const time = h > 0 ? `${h}h ${m}m` : `${m}m`
        return onBattery ? time : `+ ${time}`
    }

    // a charge limit (Lenovo conservation mode, ThinkPad thresholds) parks the battery on AC
    readonly property bool held: available && !onBattery
        && UPower.displayDevice.state === UPowerDeviceState.PendingCharge

    readonly property string statusLabel: {
        if (!available)  return ""
        if (!onBattery)  return full ? "charged" : held ? "not charging" : "charging"
        return "discharging"
    }

    // the glyph already carries the level in warning then error, so the pulse is emphasis
    // on top of a standing signal: it announces each crossing and rests, rather than
    // animating for the hours a low level holds on the machine least able to afford it
    property bool _alertSettled: false
    onLowChanged:      if (root.low) root._alertSettled = false
    onCriticalChanged: if (root.critical) root._alertSettled = false

    // nothing draws alertPulse with the pill hidden, the underline glow off and the menu shut
    readonly property bool _alertWatched: ShellSettings.barShowBattery
        || (ShellSettings.underlineGlow && ShellSettings.underlineBattGlow) || MenuState.homeActive

    PulseLoop {
        target:         root
        targetProperty: "alertPulse"
        duration:       root.pulseDuration
        active:         root.low && root._alertWatched
            && !root._alertSettled && !Idle.isQuiet
    }

    Timer {
        interval: 15000
        running: root.low && root._alertWatched && !root._alertSettled
            && !Idle.isQuiet && !ShellSettings.reduceMotion
        onTriggered: root._alertSettled = true
    }
}
