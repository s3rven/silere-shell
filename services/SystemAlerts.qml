pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // public so the shell root can force-instantiate: Quickshell lazy-loads singletons and nothing else reads SystemAlerts, so its watchers never arm otherwise
    readonly property bool armed: root.canAlert
    // the alerts reach Silere's own server over D-Bus: notify-send when it is installed, else busctl, which systemd ships.
    // Without either, a minimal install never saw its welcome, a panel that failed to load or a cancelled sleep
    readonly property bool canAlert: SystemTools.hasNotifySend || SystemTools.hasBusctl

    property bool _battCritSent: false

    // one channel per alert: the OSD carries the low tiers, and a critical one comes here because it stays on screen and
    // in history until dealt with. The OSD stands in only when this popup would not appear
    function criticalPopupFor(canSend: bool, popupsOn: bool, bypass: bool, silenced: bool): bool {
        return canSend && popupsOn && (bypass || !silenced)
    }
    readonly property bool criticalPopsUp: root.criticalPopupFor(
        SystemTools.ready && root.canAlert && Quickshell.env("SILERE_SANDBOX") !== "1",
        ShellSettings.notifPopupEnabled && !Notifications.screenShareSilenced,
        ShellSettings.notifCriticalBypass, Notifications.silencingActive)
    property bool _cpuCritSent:  false

    function alertCommand(summary: string, body: string, urgency: string, icon: string, timeout: int, click = ""): var {
        const argv = ["notify-send", "--urgency=" + urgency, "--expire-time=" + timeout, "--app-name=Silere Shell",
            "--icon=" + (icon || "dialog-information")]
        if (click.length > 0) argv.push("--hint=string:x-silere-click:" + click)
        // a bluetooth device can be named "-x": without the end of options, notify-send refuses the alert
        return argv.concat(["--", summary, body])
    }

    // the same alert as notify-send sends it: Notify(app, replaces, icon, summary, body, actions, hints, timeout), with
    // urgency as a byte and the click as a string hint. Options end before the arguments, as a summary can begin with -
    function busAlertCommand(summary: string, body: string, urgency: string, icon: string, timeout: int, click = ""): var {
        const level = urgency === "critical" ? "2" : urgency === "low" ? "0" : "1"
        const hints = ["urgency", "y", level]
        if (click.length > 0) hints.push("x-silere-click", "s", click)
        return ["busctl", "--user", "--timeout=5", "call", "--", "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
            "Silere Shell", "0", icon || "dialog-information", summary, body, "0", String(hints.length / 3)]
            .concat(hints, [String(timeout)])
    }

    function notificationCommand(summary: string, body: string, urgency: string, icon: string, timeout: int, click = ""): var {
        return SystemTools.hasNotifySend ? root.alertCommand(summary, body, urgency, icon, timeout, click)
            : root.busAlertCommand(summary, body, urgency, icon, timeout, click)
    }

    // a hint, not an action: an action keeps notify-send waiting as long as a critical alert stays up. A faked one only reloads the shell
    function isReloadAlert(notification): bool {
        return !!notification && notification.appName === "Silere Shell"
            && String(notification.hints?.["x-silere-click"] ?? "") === "reload"
    }

    function _send(summary: string, body: string, urgency: string, icon: string, click = ""): bool {
        if (!SystemTools.ready || !root.canAlert || Quickshell.env("SILERE_SANDBOX") === "1") return false
        Quickshell.execDetached(root.notificationCommand(summary, body, urgency, icon, ShellSettings.sysAlertTimeout, click))
        return true
    }

    function _shellQuote(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function runOrNotify(command, failTitle: string): void {
        if (!command || command.length === 0) return
        // a test copy must never lock, suspend or end the real session
        if (Quickshell.env("SILERE_SANDBOX") === "1") {
            console.info("silere-shell: sandboxed power action skipped:", command.join(" "))
            return
        }
        Compositor.launch(root.canAlert ? root.launchArgv(command, failTitle) : command)
    }

    // only a failure to start is reported: a lock that ran an hour, or a terminal passing on the hangup its
    // monitor got when the window closed, exits nonzero too, and alerting then calls a normal close a failure
    function launchArgv(command, failTitle: string): var {
        const alert = root.notificationCommand(failTitle,
            "It may require authorization or be blocked by a running task.", "critical", "dialog-error", -1)
        const note = alert.map(word => root._shellQuote(word)).join(" ")
        const argv = ["bash", "-c", '"$@" || [ "$SECONDS" -ge 5 ] || ' + note + " >/dev/null", "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        return argv
    }

    // for a service whose failure happens after the surface that started it has closed
    function send(summary: string, body: string, urgency: string, icon: string, click = ""): bool {
        return root._send(summary, body, urgency, icon, click)
    }

    // the way into the menu is the active workspace, and otherwise only the installer's terminal output says so.
    // The delay keeps it clear of the bar settling in on a first login
    Timer {
        interval: 2000
        running: ShellSettings.firstRun && SystemTools.ready
        onTriggered: {
            if (root._send("Welcome to Silere",
                "Click the active workspace to open the menu, or right-click it for quick actions.",
                "normal", "dialog-information")) ShellSettings.markFirstRunSeen()
        }
    }

    function _checkBattCrit(): void {
        if (Battery.available && Battery.critical && Battery.alertWarning === "critical"
                && ShellSettings.osdBatteryWarn && !_battCritSent) {
            if (_send("Battery Critical",
                Math.round(Battery.pct) + "% — plug in now",
                "critical", "battery-caution")) _battCritSent = true
        }
    }
    function _checkCpuCrit(): void {
        if (CpuTemp.critical && ShellSettings.osdTempWarn && !_cpuCritSent) {
            if (_send("CPU Critical Temperature",
                Math.round(CpuTemp.temp) + "°C — reduce load immediately",
                "critical", "dialog-warning")) _cpuCritSent = true
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
            Battery.pct, ShellSettings.batteryLowThreshold, Battery.criticalPct,
            false, root._battCritSent)
        root._battCritSent = state.critical
    }

    // a headset that reports in 10% steps can read 20 for a charge under it, so the mark itself counts as low: below it,
    // such a headset warned only at 10
    readonly property int btLowPct: 20
    // over one 10% step above the mark, so a reading that flips between 20 and 30 as it drains warns once
    readonly property int btRearmPct: 35
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
            else if (r.pct <= low) {
                next[r.address] = true
                alerts.push(r)
            }
        }
        return { warned: next, alerts: alerts }
    }

    property var _btWarned: ({})
    readonly property var _deviceReadings: {
        const out = []
        const devs = Bluetooth.allDevices
        for (let i = 0; i < devs.length; i++) {
            const d = devs[i]
            if (!d || !d.connected) continue
            out.push({ address: String(d.address), name: Bluetooth.deviceLabel(d),
                pct: Bluetooth.batteryPercent(d) })
        }
        const wired = Battery.peripherals
        for (let i = 0; i < wired.length; i++)
            out.push({ address: wired[i].id, name: wired[i].name, pct: wired[i].pct })
        return out
    }
    on_DeviceReadingsChanged: Qt.callLater(root._checkBtBatteries)
    function _checkBtBatteries(): void {
        const step = root.btAlertStep(root._btWarned, root._deviceReadings, root.btLowPct, root.btRearmPct)
        for (let i = 0; i < step.alerts.length; i++) {
            const alert = step.alerts[i]
            if (!ShellSettings.osdBatteryWarn
                    || !root._send(alert.name + " battery low", alert.pct + "%", "normal", "battery-caution"))
                delete step.warned[alert.address]
        }
        root._btWarned = step.warned
    }

    // gnome's rule: under 5% and under 2 GB free. A big disk at 5% still has room for an upgrade, a small one at 2 GB does not
    readonly property real diskLowKb: 2 * 1024 * 1024
    function diskAlertStep(warned, dfText: string): var {
        const next = {}
        const alerts = []
        const lines = String(dfText || "").split("\n")
        for (let i = 1; i < lines.length; i++) {
            const f = lines[i].trim().split(/\s+/)
            if (f.length < 6) continue
            // by device: home on the root filesystem, a btrfs subvolume included, is one disk and one warning
            const disk = f[0], size = Number(f[1]), avail = Number(f[3])
            if (!(size > 0) || !(avail >= 0) || disk in next) continue
            const limit = Math.min(root.diskLowKb, size * 0.05)
            // a quarter over the mark before it rearms, so a cache filling and emptying around it warns once
            next[disk] = avail < limit || warned[disk] === true && avail < limit * 1.25
            if (next[disk] && warned[disk] !== true) alerts.push({ disk: disk, mount: f.slice(5).join(" "), availKb: avail })
        }
        return { warned: next, alerts: alerts }
    }
    property var _diskWarned: ({})
    BoundedProcess {
        id: _df
        timeoutMs: 5000
        stdout: StdioCollector { id: _dfOut }
        onExited: code => {
            if (!_df.completedSuccessfully(code)) return
            const step = root.diskAlertStep(root._diskWarned, _dfOut.text)
            for (let i = 0; i < step.alerts.length; i++) {
                const alert = step.alerts[i]
                const free = alert.availKb < 1048576 ? Math.round(alert.availKb / 1024) + " MB"
                    : (alert.availKb / 1048576).toFixed(1) + " GB"
                if (!root._send("Disk almost full", free + " left on " + alert.mount
                        + ". Updates and apps can fail until some space is freed.", "normal", "drive-harddisk"))
                    delete step.warned[alert.disk]
            }
            root._diskWarned = step.warned
        }
    }
    // at login, then every few hours of use: one df, never while the machine sits idle
    Timer {
        interval: 4 * 3600 * 1000
        repeat: true
        triggeredOnStart: true
        running: SystemTools.ready && root.canAlert && !Idle.isIdle
        onTriggered: if (!_df.running) _df.exec(["df", "-Pk", "/", Quickshell.env("HOME") || "/"])
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
