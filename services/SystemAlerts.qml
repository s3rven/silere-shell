pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Public so the shell root can force-instantiate this singleton: Quickshell
    // lazy-loads singletons, and nothing else touches SystemAlerts, so without an
    // external member read its watchers never arm and no alert ever fires.
    readonly property bool armed: SystemTools.hasNotifySend

    // Sent-flags prevent re-firing while the condition is still true.
    // Reset when the condition clears so the next onset fires again.
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

    Connections {
        target: Battery

        function onLowChanged(): void {
            if (Battery.low && !root._battLowSent) {
                root._battLowSent = true
                if (ShellSettings.osdBatteryWarn)
                    root._send("Battery Low",
                        Math.round(Battery.pct) + "% remaining — consider plugging in",
                        "normal")
            } else if (!Battery.low) {
                root._battLowSent  = false
                root._battCritSent = false
            }
        }

        function onCriticalChanged(): void {
            if (Battery.critical && !root._battCritSent) {
                root._battCritSent = true
                if (ShellSettings.osdBatteryWarn)
                    root._send("Battery Critical",
                        Math.round(Battery.pct) + "% — plug in now",
                        "critical")
            } else if (!Battery.critical) {
                root._battCritSent = false
            }
        }
    }

    Connections {
        target: CpuTemp

        // only critical notifies — "hot" is normal under load and already shown by OSD/glow
        function onCriticalChanged(): void {
            if (CpuTemp.critical && !root._cpuCritSent) {
                root._cpuCritSent = true
                if (ShellSettings.osdTempWarn)
                    root._send("CPU Critical Temperature",
                        Math.round(CpuTemp.temp) + "°C — reduce load immediately",
                        "critical")
            } else if (!CpuTemp.critical) {
                root._cpuCritSent = false
            }
        }
    }
}
