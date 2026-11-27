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
    readonly property int  criticalPct: Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2))
    // pct > 0 again here: a gate on a sibling binding can run a step behind pct and pass the placeholder
    readonly property bool low: available && pct > 0 && pct < ShellSettings.batteryLowThreshold && onBattery
    readonly property bool critical: available && pct > 0 && pct < criticalPct && onBattery
    readonly property int state: upowerReady ? UPower.displayDevice.state : UPowerDeviceState.Unknown
    readonly property bool onAc: available && !onBattery
    readonly property bool charging: available && state === UPowerDeviceState.Charging
    readonly property bool full: available && (pct >= 99 || state === UPowerDeviceState.FullyCharged)
    readonly property int pulseDuration: critical ? Motion.ms(650) : Motion.ms(2000)
    property real alertPulse: 0

    function _stateColor(idle: color, active: color, rest: color,
                         good: color, bad: color, low: color): color {
        if (!available)                               return idle
        if (onAc && full)                             return good
        if (held)                                     return idle
        if (charging)                                 return active
        if (pct < criticalPct)                           return bad
        if (pct < ShellSettings.batteryLowThreshold)  return low
        return rest
    }
    readonly property color iconColor: _stateColor(Theme.subtext, Theme.accent, Theme.accent,
        Theme.success, Theme.error, Theme.warning)
    // the bar's own tokens, lifted for contrast over the bar; a battery at rest is neutral like every other
    // reading, so "pills follow theming" decides whether it takes the accent
    readonly property color barIconColor: _stateColor(Theme.barSubtext, Theme.barAccentMark, Theme.barText,
        Theme.barSuccess, Theme.barError, Theme.barWarning)

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

    function _powerDevices(values): var {
        return (values || []).filter(d => d && d.ready && d.isPresent && d.powerSupply
            && (d.type === UPowerDeviceType.Battery || d.type === UPowerDeviceType.Ups))
    }

    // mice, keyboards, pads and headsets on their own receivers; the ones BlueZ connects are Bluetooth's to watch
    readonly property var _peripheralGlyphs: ({
        [UPowerDeviceType.Mouse]: "󰍽", [UPowerDeviceType.Keyboard]: "󰌌", [UPowerDeviceType.GamingInput]: "󰊗",
        [UPowerDeviceType.Touchpad]: "󰝁", [UPowerDeviceType.Tablet]: "󰓶", [UPowerDeviceType.Pen]: "󱦹",
        [UPowerDeviceType.Headset]: "󰋎", [UPowerDeviceType.Headphones]: "󰋋"
    })
    function peripheralsFrom(values): var {
        const out = []
        for (const d of values || []) {
            if (!d || !d.ready || !d.isPresent || d.powerSupply || !(d.type in root._peripheralGlyphs)
                    || String(d.nativePath || "").startsWith("/org/bluez/") || !(d.percentage > 0)) continue
            const name = SafeText.singleLineText(d.model || "", 96)
            out.push({ id: String(d.nativePath || name), glyph: root._peripheralGlyphs[d.type],
                name: name || UPowerDeviceType.toString(d.type), pct: Math.round(root.normalizedPercent(d.percentage)) })
        }
        return out
    }
    readonly property var peripherals: root.peripheralsFrom(UPower.devices ? UPower.devices.values : [])
    // with no battery of its own, the bar shows the lowest of these, and only while it is low
    function lowPeripheralOf(list): var {
        let low = null
        for (const p of list || []) if (p && p.pct <= 20 && (!low || p.pct < low.pct)) low = p
        return low
    }
    readonly property var lowPeripheral: root.available ? null : root.lowPeripheralOf(root.peripherals)

    readonly property StableObjectList _detailDevices: StableObjectList {
        source: root._powerDevices(UPower.devices ? UPower.devices.values : [])
    }
    readonly property var detailDevices: root._detailDevices.values
    readonly property var details: root.detailsFor(root.detailDevices)
    // what the details panel draws: one battery repeats nothing of the reading above it, so it needs a measurement of its own
    function detailsShown(list): bool {
        return list.length > 1 || list.some(d => d.health.length > 0 || d.energy.length > 0 || d.power.length > 0)
    }
    readonly property bool hasDetails: root.detailsShown(root.details)

    function _measurement(value): bool {
        return typeof value === "number" && isFinite(value) && value >= 0
    }

    function measurementText(value: real): string {
        return value.toFixed(1).replace(/\.0$/, "")
    }

    function detailsFor(devices): var {
        const list = root._powerDevices(devices)
        return list.map(device => root.detailFor(device, list))
    }

    function detailFor(device, list): var {
        device = device ?? ({})
        const ups = device.type === UPowerDeviceType.Ups
        const base = ups ? "UPS" : "Battery"
        const name = SafeText.singleLineText(device.model || "", 96)
        const state = device.state ?? UPowerDeviceState.Unknown
        const charging = state === UPowerDeviceState.Charging
        const discharging = state === UPowerDeviceState.Discharging
        const charge = root._measurement(device.percentage)
            ? root.normalizedPercent(device.percentage) : -1
        // health is UPower's Capacity in 0-100; only charge is scaled to 0-1
        const health = device.healthSupported && root._measurement(device.healthPercentage)
            && device.healthPercentage > 0 ? Math.min(100, device.healthPercentage) : -1
        const energy = root._measurement(device.energy) && root._measurement(device.energyCapacity)
            && device.energyCapacity > 0
            ? root.measurementText(device.energy) + " / " + root.measurementText(device.energyCapacity) + " Wh" : ""
        // UPower's EnergyRate is negative while charging by its spec; some backends report it that way
        const rate = charging && typeof device.changeRate === "number" ? Math.abs(device.changeRate) : device.changeRate
        const power = (charging || discharging) && root._measurement(rate) && rate > 0
            ? root.measurementText(rate) + " W" : ""
        // numbered within their own kind: a laptop beside a UPS is "Battery" and "UPS", not 1 and 2
        const kind = list.filter(d => d && d.type === device.type)
        return { name: kind.length <= 1 ? base : base + " " + (kind.indexOf(device) + 1), model: name,
            // the kernel's name for it, which ties the row to its charge limit
            nativePath: String(device.nativePath || ""),
            charge: charge >= 0 ? Math.round(charge) + "%" : "",
            state: state === UPowerDeviceState.PendingCharge ? "not charging"
                : root.statusFor(true, state, discharging, state === UPowerDeviceState.FullyCharged),
            health: health >= 0 ? Math.round(health) + "%" : "", energy: energy,
            power: power, powerLabel: charging ? "Charging power" : "Power use" }
    }

    // rescale UPower's estimate by time spent at each draw, since the rate signal only fires on changes
    readonly property real _rateNow: upowerReady ? Math.abs(Number(UPower.displayDevice.changeRate) || 0) : 0
    property var _rates: []
    property real _meanRate: 0
    on_RateNowChanged: {
        DateTime.catchUp()
        Qt.callLater(root._sampleRate)
    }
    onStateChanged: root._restartWindow()
    Connections {
        target: DateTime
        function onWoke() { root._restartWindow() }
    }
    function _restartWindow(): void {
        root._rates = []
        root._meanRate = 0
        Qt.callLater(root._sampleRate)
    }
    function _sampleRate(): void {
        const active = root.available && (root.charging || root.state === UPowerDeviceState.Discharging)
        root._noteRate(active ? root._rateNow : 0, Date.now())
    }
    function _noteRate(watts: real, now: real): void {
        if (!isFinite(watts) || watts <= 0) {
            root._rates = []
            root._meanRate = 0
            return
        }
        const last = root._rates[root._rates.length - 1]
        // a backwards clock jump starts a fresh window
        const cutoff = now - 300000
        let first = 0
        while (first + 1 < root._rates.length && root._rates[first + 1][0] <= cutoff) first++
        const samples = last && last[0] <= now ? root._rates.slice(first) : []
        if (last && last[0] === now) samples[samples.length - 1] = [now, watts]
        else if (samples.length === 0 || last[1] !== watts) samples.push([now, watts])
        const duration = now - Math.max(cutoff, samples[0][0])
        let weighted = 0
        for (let i = 0; i < samples.length; i++) {
            const end = i + 1 < samples.length ? samples[i + 1][0] : now
            weighted += samples[i][1] * (end - Math.max(cutoff, samples[i][0]))
        }
        root._rates = samples
        root._meanRate = duration > 0 ? weighted / duration : watts
    }
    // steady power can send no new rate signal for minutes while an older interval ages out
    readonly property Timer _rateAge: Timer {
        interval: 30000
        repeat: true
        running: root._rates.length > 1 && !Idle.isIdle
        onTriggered: root._sampleRate()
    }
    function steadyTime(seconds: real, rateNow: real, meanRate: real): real {
        return seconds > 0 && rateNow > 0 && meanRate > 0 ? seconds * rateNow / meanRate : seconds
    }
    readonly property real   timeToEmpty: upowerReady
        ? root.steadyTime(UPower.displayDevice.timeToEmpty, root._rateNow, root._meanRate) : 0
    readonly property real   timeToFull:  upowerReady ? root.timeToStop(
        root.steadyTime(UPower.displayDevice.timeToFull, root._rateNow, root._meanRate), root.pct, root.chargeStop) : 0

    // UPower counts to 100% under a charge limit too, and Lenovo's names no stop: the level the battery was last held at is it
    property int heldAt: 0
    // some firmware reports a full battery on AC as held too: that is no limit
    onHeldChanged: if (root.held && root.pct < 99) root.heldAt = Math.max(root.heldAt, Math.round(root.pct))
    // charging on past it: the limit was switched off, or that hold had another cause
    readonly property bool _passedStop: root.charging && root.heldAt > 0 && root.pct > root.heldAt + 1
    // later, and only if still past: clearing heldAt inside this handler re-enters the binding it reads (a binding loop)
    on_PassedStopChanged: if (root._passedStop) Qt.callLater(root._forgetPassedStop)
    function _forgetPassedStop(): void {
        if (root._passedStop) root.heldAt = 0
    }
    readonly property int chargeStop: root.charging && root.heldAt >= root.pct ? root.heldAt : 0
    function timeToStop(seconds: real, level: real, stop: int): real {
        return stop > 0 && stop >= level && level < 100 ? seconds * (stop - level) / (100 - level) : seconds
    }
    readonly property string timeLabel: {
        if (!available) return ""
        if (charging) return root.timeText(timeToFull)
        if (state === UPowerDeviceState.Discharging || onBattery)
            return root.timeText(timeToEmpty)
        return ""
    }
    readonly property string estimateLabel: root.estimateFor(timeLabel, charging, chargeStop)

    function timeText(seconds: real): string {
        if (!isFinite(seconds) || seconds <= 0) return ""
        const minutes = Math.ceil(seconds / 60)
        const h = Math.floor(minutes / 60), m = minutes % 60
        return h > 0 ? `${h}h ${m}m` : `${m}m`
    }

    function estimateFor(duration: string, charging: bool, stop: int): string {
        if (duration.length === 0) return ""
        if (charging) return (stop > 0 ? stop + "% in " : "Full in ") + duration
        return duration + " left"
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

    // one settled reading shared by desktop notifications and the OSD; the first valid one is the baseline
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
        // a login below the low threshold stays quiet, but critical still needs plugging in now
        if (!previous) {
            return { lowSeen: low, criticalSeen: critical, warning: critical ? "critical" : "",
                chargeObserved: charging && !full && !onBattery,
                fullSeen: full, chargeRevision: 0, chargeComplete: false }
        }

        let lowSeen = previous.lowSeen && onBattery && pct < lowThreshold + 2
        let criticalSeen = previous.criticalSeen && onBattery && pct < criticalThreshold + 2
        let warning = critical ? previous.warning : low && previous.warning === "low" ? "low" : ""
        if (critical && !criticalSeen) warning = "critical"
        else if (low && !lowSeen) warning = "low"
        // a jump directly into critical counts as both crossings
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
            ShellSettings.batteryLowThreshold, root.criticalPct)
    }

    // UPower's percentage, power source and state can update in one event turn.
    // Reading them together avoids transient low/critical pairs and AC alerts
    onAvailableChanged: {
        Qt.callLater(root._updateNotificationState)
        Qt.callLater(root._sampleRate)
    }
    onPctChanged: Qt.callLater(root._updateNotificationState)
    onOnBatteryChanged: Qt.callLater(root._updateNotificationState)
    onChargingChanged: Qt.callLater(root._updateNotificationState)
    onFullChanged: Qt.callLater(root._updateNotificationState)
    Component.onCompleted: {
        Qt.callLater(root._updateNotificationState)
        Qt.callLater(root._sampleRate)
    }

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
