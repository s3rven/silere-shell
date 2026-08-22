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

    function _send(summary: string, body: string, urgency: string): bool {
        if (!SystemTools.ready || !SystemTools.hasNotifySend) return false
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
        if (Battery.low && ShellSettings.osdBatteryWarn && !_battLowSent) {
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
        if (Battery.critical) _checkBattCrit()
        else _checkBattLow()
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
            if (Battery.low) {
                root._checkBattLow()
            } else {
                root._battLowSent  = false
                root._battCritSent = false
            }
        }

        function onCriticalChanged(): void {
            if (Battery.critical) root._checkBattCrit()
            else root._battCritSent = false
        }
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
