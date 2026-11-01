pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // public so the shell root can force-instantiate: Quickshell lazy-loads singletons and nothing else reads SystemAlerts, so its watchers never arm otherwise
    readonly property bool armed: SystemTools.hasNotifySend

    property bool _battCritSent: false

    // one channel per alert: the OSD carries the low tiers, and a critical one comes here because it stays on screen and
    // in history until dealt with. The OSD stands in only when this popup would not appear
    function criticalPopupFor(canSend: bool, popupsOn: bool, bypass: bool, silenced: bool): bool {
        return canSend && popupsOn && (bypass || !silenced)
    }
    readonly property bool criticalPopsUp: root.criticalPopupFor(
        SystemTools.ready && SystemTools.hasNotifySend && Quickshell.env("SILERE_SANDBOX") !== "1",
        ShellSettings.notifPopupEnabled && !Notifications.screenShareSilenced,
        ShellSettings.notifCriticalBypass, Notifications.silencingActive)
    property bool _cpuCritSent:  false

    function _send(summary: string, body: string, urgency: string): bool {
        if (!SystemTools.ready || !SystemTools.hasNotifySend
                || Quickshell.env("SILERE_SANDBOX") === "1") return false
        Quickshell.execDetached([
            "notify-send",
            "--urgency=" + urgency,
            "--expire-time=" + ShellSettings.sysAlertTimeout,
            "--app-name=silere-shell",
            summary,
            body
        ])
        return true
    }

    // for a service whose failure happens after the surface that started it has closed
    function send(summary: string, body: string, urgency: string): bool {
        return root._send(summary, body, urgency)
    }

    // the way into the menu is the active workspace, and otherwise only the installer's terminal output says so.
    // The delay keeps it clear of the bar settling in on a first login
    Timer {
        interval: 2000
        running: ShellSettings.firstRun && SystemTools.ready
        onTriggered: {
            if (root._send("Welcome to Silere",
                "Click the active workspace to open the menu, or right-click it for quick actions.",
                "normal")) ShellSettings.markFirstRunSeen()
        }
    }

    function _checkBattCrit(): void {
        if (Battery.available && Battery.critical && Battery.alertWarning === "critical"
                && ShellSettings.osdBatteryWarn && !_battCritSent) {
            if (_send("Battery Critical",
                Math.round(Battery.pct) + "% — plug in now",
                "critical")) _battCritSent = true
        }
    }
    function _checkCpuCrit(): void {
        if (CpuTemp.critical && ShellSettings.osdTempWarn && !_cpuCritSent) {
            if (_send("CPU Critical Temperature",
                Math.round(CpuTemp.temp) + "°C — reduce load immediately",
                "critical")) _cpuCritSent = true
        }
    }

    function _checkCurrentWarnings(): void {
        if (Battery.alertWarning === "critical") _checkBattCrit()
        _checkCpuCrit()
        _checkBtBatteries()
    }

    Component.onCompleted: Qt.callLater(root._checkCurrentWarnings)

    Connections {
        target: SystemTools
        function onReadyChanged(): void {
            if (SystemTools.ready) root._checkCurrentWarnings()
        }
        function onScanRevisionChanged(): void {
            root._checkCurrentWarnings()
        }
    }

    Connections {
        target: Battery

        function onAlertWarningChanged(): void {
            root._rearmBattery()
            root._checkCurrentWarnings()
        }

        function onPctChanged(): void {
            Qt.callLater(root._rearmBattery)
        }
        function onOnBatteryChanged(): void { Qt.callLater(root._rearmBattery) }
    }

    // a reading that wobbles across the threshold must not send the warning again
    function batteryRearmState(available: bool, onBattery: bool, pct: real,
            lowThreshold: real, criticalThreshold: real,
            lowSent: bool, criticalSent: bool): var {
        if (!available) return { low: lowSent, critical: criticalSent }
        const plugged = !onBattery
        return {
            low: lowSent && !(plugged || pct >= lowThreshold + 2),
            critical: criticalSent && !(plugged || pct >= criticalThreshold + 2)
        }
    }
    function _rearmBattery(): void {
        const state = root.batteryRearmState(Battery.available, Battery.onBattery,
            Battery.pct, ShellSettings.batteryLowThreshold, Battery._critPct,
            false, root._battCritSent)
        root._battCritSent = state.critical
    }

    readonly property int btLowPct: 20
    readonly property int btRearmPct: 25
    function btAlertStep(warned, readings, low: int, rearm: int): var {
        const next = {}
        const alerts = []
        for (let i = 0; i < readings.length; i++) {
            const r = readings[i]
            if (typeof r.pct !== "number" || !isFinite(r.pct) || r.pct < 0 || r.pct > 100) {
                if (warned[r.address] === true) next[r.address] = true
                continue
            }
            if (r.pct >= rearm) continue
            if (warned[r.address] === true) next[r.address] = true
            else if (r.pct < low) {
                next[r.address] = true
                alerts.push(r)
            }
        }
        return { warned: next, alerts: alerts }
    }

    property var _btWarned: ({})
    readonly property var _btReadings: {
        const out = []
        const devs = Bluetooth._devices
        for (let i = 0; i < devs.length; i++) {
            const d = devs[i]
            if (!d || !d.connected) continue
            out.push({ address: String(d.address), name: Bluetooth.deviceLabel(d),
                pct: Bluetooth.batteryPercent(d) })
        }
        return out
    }
    on_BtReadingsChanged: Qt.callLater(root._checkBtBatteries)
    function _checkBtBatteries(): void {
        const step = root.btAlertStep(root._btWarned, root._btReadings, root.btLowPct, root.btRearmPct)
        for (let i = 0; i < step.alerts.length; i++) {
            const alert = step.alerts[i]
            if (!ShellSettings.osdBatteryWarn
                    || !root._send(alert.name + " battery low", alert.pct + "%", "normal"))
                delete step.warned[alert.address]
        }
        root._btWarned = step.warned
    }

    Connections {
        target: CpuTemp

        function onCriticalChanged(): void {
            if (CpuTemp.critical) root._checkCpuCrit()
            else root._cpuCritSent = false
        }
    }

    Connections {
        target: ShellSettings

        function onOsdBatteryWarnChanged(): void {
            if (Battery.alertWarning === "critical") root._checkBattCrit()
            root._checkBtBatteries()
        }
        function onOsdTempWarnChanged(): void {
            root._checkCpuCrit()
        }
    }
}
