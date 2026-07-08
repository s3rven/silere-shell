pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // public so the shell root can force-instantiate: Quickshell lazy-loads singletons and nothing else reads SystemAlerts, so its watchers never arm otherwise
    readonly property bool armed: SystemTools.hasNotifySend

    // sent-flags prevent re-firing while the condition holds; reset when it clears so the next onset fires
    property bool _battLowSent:  false
    property bool _battCritSent: false
    property bool _cpuCritSent:  false

    function _send(summary: string, body: string, urgency: string): void {
        if (!SystemTools.ready || !SystemTools.hasNotifySend) return
        Quickshell.execDetached([
            "notify-send",
            "--urgency=" + urgency,
            // explicit timeout so even critical alerts auto-dismiss; configurable (0 = stay)
            "--expire-time=" + ShellSettings.sysAlertTimeout,
            "--app-name=silere-shell",
            summary,
            body
        ])
    }

    // latch only when a notification actually sends, so enabling the toggle mid-condition still alerts
    function _checkBattLow(): void {
        if (Battery.low && ShellSettings.osdBatteryWarn && !_battLowSent) {
            _battLowSent = true
            _send("Battery Low",
                Math.round(Battery.pct) + "% remaining — consider plugging in",
                "normal")
        }
    }
    function _checkBattCrit(): void {
        if (Battery.critical && ShellSettings.osdBatteryWarn && !_battCritSent) {
            _battCritSent = true
            _send("Battery Critical",
                Math.round(Battery.pct) + "% — plug in now",
                "critical")
        }
    }
    function _checkCpuCrit(): void {
        if (CpuTemp.critical && ShellSettings.osdTempWarn && !_cpuCritSent) {
            _cpuCritSent = true
            _send("CPU Critical Temperature",
                Math.round(CpuTemp.temp) + "°C — reduce load immediately",
                "critical")
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

        // only critical notifies — "hot" is normal under load and already shown by OSD/glow
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
