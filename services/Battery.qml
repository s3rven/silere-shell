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
    // UPower reports 0-1 on some setups, 0-100 on others; once we see a value
    // above 1 we know it's the 0-100 kind and keep treating it that way.
    readonly property real _raw: upowerReady ? UPower.displayDevice.percentage : 0
    property bool _scale100: false
    property real _pctOverride: -1
    property bool _ambiguousTried: false
    Binding {
        target: root
        property: "_scale100"
        value: true
        when: root._raw > 1.0
        restoreMode: Binding.RestoreNone
    }
    readonly property bool _ambiguousRawOne: available && !_scale100 && Math.abs(_raw - 1) < 0.0001
    readonly property real pct: (_ambiguousRawOne && _pctOverride >= 0)
        ? _pctOverride
        : (_scale100 ? _raw : (_raw * 100))
    readonly property bool onBattery: available ? UPower.onBattery : false
    readonly property int  _critPct: Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2))
    // pct == 0 is UPower's uninitialised reading just after displayDevice goes ready;
    // treating it as valid fires a bogus "Critical 0%" alert at startup.
    readonly property bool _validReading: available && pct > 0
    readonly property bool low: _validReading && pct < ShellSettings.batteryLowThreshold && onBattery
    readonly property bool critical: _validReading && pct < _critPct && onBattery
    readonly property bool charging: available && !onBattery
    readonly property bool full:     available && pct >= 99
    readonly property int pulseDuration: critical ? 650 : 2000
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
        if (pct >= 90)   return "󰁹"
        if (pct >= 80)   return "󰂂"
        if (pct >= 70)   return "󰂁"
        if (pct >= 60)   return "󰂀"
        if (pct >= 50)   return "󰁿"
        if (pct >= 40)   return "󰁾"
        if (pct >= 30)   return "󰁽"
        if (pct >= 20)   return "󰁼"
        if (pct >= 10)   return "󰁻"
        return "󰁺"
    }

    readonly property string label: _validReading ? `${Math.round(pct)}%` : ""

    Timer {
        interval: 0
        running: root._ambiguousRawOne && root._pctOverride < 0 && !root._ambiguousTried
        onTriggered: {
            root._ambiguousTried = true
            _percentProbe.running = true
        }
    }

    Process {
        id: _percentProbe
        running: false
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

    readonly property string statusLabel: {
        if (!available)  return ""
        if (!onBattery)  return "charging"
        return "discharging"
    }

    // Power flow in/out of the battery (W). Shown in the menu gauge while charging.
    readonly property real   changeRate: upowerReady ? Math.abs(UPower.displayDevice.changeRate) : 0
    readonly property string rateLabel:  (available && changeRate > 0.1) ? changeRate.toFixed(1) + "W" : ""

    // Shared low-battery pulse. The bar underline and battery pill both bind to
    // this value, so critical battery warnings stay phase-locked.
    PulseLoop {
        target:         root
        targetProperty: "alertPulse"
        duration:       root.pulseDuration
        running:        root.low && !ShellSettings.reduceMotion && !Idle.isIdle
    }
}
