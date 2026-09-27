pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // public so the shell root can force-instantiate: Quickshell lazy-loads singletons and nothing else reads SystemAlerts, so its watchers never arm otherwise
    readonly property bool armed: SystemTools.hasNotifySend

    property bool _battLowSent:  false
    property bool _battCritSent: false
    property bool _cpuCritSent:  false

    function batteryWarningLevel(low: bool, critical: bool): string {
        if (critical) return "critical"
        return low ? "low" : ""
    }

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

    function _checkBattLow(): void {
        // one backend update can cross both thresholds; critical wins so the jump sends one
        if (root.batteryWarningLevel(Battery.low, Battery.critical) === "low"
                && ShellSettings.osdBatteryWarn && !_battLowSent) {
            if (_send("Battery Low",
                Math.round(Battery.pct) + "% remaining — consider plugging in",
                "normal")) _battLowSent = true
        }
    }
    function _checkBattCrit(): void {
        if (Battery.critical && ShellSettings.osdBatteryWarn && !_battCritSent) {
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
        const level = root.batteryWarningLevel(Battery.low, Battery.critical)
        if (level === "critical") _checkBattCrit()
        else if (level === "low") _checkBattLow()
        _checkCpuCrit()
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

        function onLowChanged(): void {
            if (Battery.low) root._checkBattLow()
            else root._rearmBattery()
        }

        function onCriticalChanged(): void {
            if (Battery.critical) root._checkBattCrit()
            else root._rearmBattery()
        }

        function onPctChanged(): void {
            if (root._battLowSent || root._battCritSent) root._rearmBattery()
        }
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
            root._battLowSent, root._battCritSent)
        root._battLowSent = state.low
        root._battCritSent = state.critical
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
            if (Battery.critical) root._checkBattCrit()
            else root._checkBattLow()
        }
        function onOsdTempWarnChanged(): void {
            root._checkCpuCrit()
        }
    }
}
