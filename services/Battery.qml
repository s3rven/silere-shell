pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../config"

Singleton {
    id: root

    readonly property bool upowerReady: UPower.displayDevice && UPower.displayDevice.ready
    readonly property bool present: upowerReady && UPower.displayDevice.isPresent
    // quickshell scales upower's 0-100 to 0-1 as it reads it
    readonly property real _raw: upowerReady ? UPower.displayDevice.percentage : 0

    function normalizedPercent(raw): real {
        const value = Number(raw)
        if (!isFinite(value) || value <= 0) return 0
        return Math.max(0, Math.min(100, value * 100))
    }

    readonly property real pct: root.normalizedPercent(_raw)
    // 0% is UPower's placeholder until upowerd reads the battery, sent with an inferred Empty or Charging
    function validReading(isPresent: bool, level: real): bool {
        return isPresent && isFinite(level) && level > 0
    }
    readonly property bool available: root.validReading(present, pct)
    readonly property bool onBattery: available ? UPower.onBattery : false
    readonly property int  _critPct: Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2))
    // pct > 0 again here: a gate on a sibling binding can run a step behind pct and pass the placeholder
    readonly property bool low: available && pct > 0 && pct < ShellSettings.batteryLowThreshold && onBattery
    readonly property bool critical: available && pct > 0 && pct < _critPct && onBattery
    readonly property int state: upowerReady ? UPower.displayDevice.state : UPowerDeviceState.Unknown
    readonly property bool onAc: available && !onBattery
    readonly property bool charging: available && state === UPowerDeviceState.Charging
    readonly property bool full: available && (pct >= 99 || state === UPowerDeviceState.FullyCharged)
    readonly property int pulseDuration: critical ? Motion.ms(650) : Motion.ms(2000)
    property real alertPulse: 0

    readonly property color iconColor: {
        if (!available)                               return Theme.subtext
        if (onAc && full)                             return Theme.success
        if (held)                                     return Theme.subtext
        if (charging)                                 return Theme.accent
        if (pct < _critPct)                           return Theme.error
        if (pct < ShellSettings.batteryLowThreshold)  return Theme.warning
        return Theme.accent
    }

    readonly property string icon: {
        if (!available)                    return "󰂎"
        if (held)                          return "󰚥"
        if (charging) {
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

    readonly property string label: available ? `${Math.round(pct)}%` : ""

    readonly property real   timeToEmpty: upowerReady ? UPower.displayDevice.timeToEmpty : 0
    readonly property real   timeToFull:  upowerReady ? UPower.displayDevice.timeToFull  : 0
    readonly property string timeLabel: {
        if (!available) return ""
        if (charging) return root.timeText(timeToFull, true)
        if (state === UPowerDeviceState.Discharging || onBattery)
            return root.timeText(timeToEmpty, false)
        return ""
    }

    function timeText(seconds: real, charging: bool): string {
        if (!isFinite(seconds) || seconds <= 0) return ""
        const minutes = Math.ceil(seconds / 60)
        const h = Math.floor(minutes / 60), m = minutes % 60
        const text = h > 0 ? `${h}h ${m}m` : `${m}m`
        return charging ? `+ ${text}` : text
    }

    // a charge limit (Lenovo conservation mode, ThinkPad thresholds) parks the battery on AC
    readonly property bool held: onAc
        && UPower.displayDevice.state === UPowerDeviceState.PendingCharge

    readonly property string statusLabel: root.statusFor(available, state, onBattery, full)

    function statusFor(present: bool, deviceState: int, onBattery: bool, full: bool): string {
        if (!present) return ""
        if (full && !onBattery) return "charged"
        if (deviceState === UPowerDeviceState.FullyCharged) return "charged"
        if (deviceState === UPowerDeviceState.Charging) return "charging"
        if (deviceState === UPowerDeviceState.Discharging) return "discharging"
        if (deviceState === UPowerDeviceState.Empty) return "empty"
        if (deviceState === UPowerDeviceState.PendingCharge) return onBattery ? "not charging" : "charge limit"
        if (deviceState === UPowerDeviceState.PendingDischarge) return "not discharging"
        return onBattery ? "on battery" : "on AC"
    }

    // Share one settled reading between desktop notifications and the OSD. The
    // first valid reading is a baseline, even when UPower arrives late at login.
    property var _notificationState: null
    readonly property string alertWarning: _notificationState ? _notificationState.warning : ""
    readonly property int chargeRevision: _notificationState ? _notificationState.chargeRevision : 0
    readonly property bool chargeComplete: _notificationState ? _notificationState.chargeComplete : false

    function notificationStateFor(previous, available: bool, pct: real,
            onBattery: bool, charging: bool, full: bool,
            lowThreshold: real, criticalThreshold: real): var {
        if (!available || !isFinite(pct) || pct <= 0) return previous
        const low = onBattery && pct < lowThreshold
        const critical = onBattery && pct < criticalThreshold
        if (!previous) {
            return { lowSeen: low, criticalSeen: critical, warning: "",
                chargeObserved: charging && !full && !onBattery,
                fullSeen: full, chargeRevision: 0, chargeComplete: false }
        }

        let lowSeen = previous.lowSeen && onBattery && pct < lowThreshold + 2
        let criticalSeen = previous.criticalSeen && onBattery && pct < criticalThreshold + 2
        let warning = critical ? previous.warning : low && previous.warning === "low" ? "low" : ""
        if (critical && !criticalSeen) warning = "critical"
        else if (low && !lowSeen) warning = "low"
        // A jump directly into critical counts as both crossings.
        lowSeen = lowSeen || low
        criticalSeen = criticalSeen || critical

        let fullSeen = previous.fullSeen && !onBattery && pct >= 97
        let chargeObserved = previous.chargeObserved && !onBattery
        let chargeRevision = previous.chargeRevision
        let chargeComplete = previous.chargeComplete && full && !onBattery
        if (charging && !full && !onBattery && !fullSeen) chargeObserved = true
        if (full && !onBattery) {
            if (chargeObserved && !fullSeen) {
                chargeRevision++
                chargeComplete = true
            }
            fullSeen = true
            chargeObserved = false
        }
        return { lowSeen: lowSeen, criticalSeen: criticalSeen, warning: warning,
            chargeObserved: chargeObserved, fullSeen: fullSeen,
            chargeRevision: chargeRevision, chargeComplete: chargeComplete }
    }

    function _updateNotificationState(): void {
        if (!ShellSettings.ready) return
        root._notificationState = root.notificationStateFor(root._notificationState,
            root.available, root.pct, root.onBattery, root.charging, root.full,
            ShellSettings.batteryLowThreshold, root._critPct)
    }

    // UPower's percentage, power source and state can update in one event turn.
    // Reading them together avoids transient low/critical pairs and AC alerts.
    onAvailableChanged: Qt.callLater(root._updateNotificationState)
    onPctChanged: Qt.callLater(root._updateNotificationState)
    onOnBatteryChanged: Qt.callLater(root._updateNotificationState)
    onChargingChanged: Qt.callLater(root._updateNotificationState)
    onFullChanged: Qt.callLater(root._updateNotificationState)
    Component.onCompleted: Qt.callLater(root._updateNotificationState)

    Connections {
        target: ShellSettings
        function onReadyChanged(): void { Qt.callLater(root._updateNotificationState) }
        function onBatteryLowThresholdChanged(): void { Qt.callLater(root._updateNotificationState) }
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
