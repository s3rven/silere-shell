pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool armed: true
    property string copyState: ""
    property string copyError: ""

    // only an explicit copy or IPC request builds a snapshot; no device polling or identifiers
    function snapshot(): var {
        return { schemaVersion: 1, compositor: Compositor.backend,
            screens: (Quickshell.screens || []).map(s => ({ width: s.width, height: s.height, scale: s.devicePixelRatio })),
            audio: { ready: Audio.backendReady, outputReady: Audio.ready, inputReady: Audio.micReady,
                outputs: Audio.sinkCount, inputs: Audio.sourceCount, recordingApps: Audio.captureCount },
            brightness: { toolAvailable: Brightness.toolAvailable, ready: Brightness.controllable,
                devices: Brightness.devices.length, writeFailed: Brightness.lastError.length > 0 },
            externalBrightness: { enabled: ShellSettings.ddcBrightnessEnabled, available: DisplayBrightness.available,
                displays: DisplayBrightness.displays.length, scanning: DisplayBrightness.scanning,
                failed: DisplayBrightness.lastError.length > 0 },
            keyboardBrightness: { toolAvailable: KeyboardBrightness.toolAvailable, ready: KeyboardBrightness.ready,
                devices: KeyboardBrightness.devices.length, failed: KeyboardBrightness.lastError.length > 0 },
            bluetooth: { available: Bluetooth.available, controllers: Bluetooth.adapterCount,
                enabled: Bluetooth.enabled, hardBlocked: Bluetooth.hardBlocked, connected: Bluetooth.connectedCount },
            network: { available: Network.toolAvailable, connected: Network.connected,
                wifiAvailable: Network.hasWifiDevice, wifiEnabled: Network.wifiEnabled,
                hardBlocked: Network.wifiHardBlocked, connectivity: Network.connectivityIssue, vpn: Network.hasVpn },
            battery: { present: Battery.present, available: Battery.available, devices: Battery.details.length } }
    }

    function checks(): var {
        const rows = []
        const add = (id, glyph, title, detail, state, action, warning) => rows.push({
            id: id, glyph: glyph, title: title, detail: detail, state: state,
            action: action || "", warning: !!warning })
        const detected = (n, thing) => n + " " + thing + (n === 1 ? "" : "s") + " detected"
        const soundAction = Audio.hasSoundSettings ? "sound" : ""
        add("audio", "󰕾", "Sound output", Audio.sinkName || (Audio.backendReady
                ? "No output device detected" : "PipeWire is not connected"),
            Audio.ready ? "Ready" : "Unavailable", soundAction, !Audio.backendReady && SystemTools.hasWpctl)
        add("microphone", "󰍬", "Microphone", Audio.sourceName || (Audio.backendReady
                ? "No input device detected" : "PipeWire is not connected"),
            Audio.micReady ? (Audio.micMuted ? "Muted" : "Ready") : "Unavailable", soundAction, false)
        if (Brightness.toolAvailable || Brightness.devices.length > 0)
            add("brightness", "󰃟", "Display backlight", Brightness.lastError
                    || (Brightness.deviceName.length > 0 ? Brightness.deviceKind(Brightness.deviceName) || Brightness.deviceName
                        : "No display backlight detected"),
                Brightness.lastError.length > 0 ? "Retry" : Brightness.controllable ? "Ready" : "Check",
                "brightness", Brightness.lastError.length > 0)
        if (ShellSettings.ddcBrightnessEnabled && !DisplayBrightness.available)
            add("externalBrightness", "󰍹", "External brightness", "Needs ddcutil and timeout", "Unavailable", "", false)
        else if (ShellSettings.ddcBrightnessEnabled)
            add("externalBrightness", "󰍹", "External brightness", DisplayBrightness.lastError
                    || (DisplayBrightness.scanning ? "Checking displays…" : detected(DisplayBrightness.displays.length, "display")),
                // the row always rescans, but a working scan reads Ready like the backlight row, not Retry
                DisplayBrightness.scanning ? "Checking"
                    : DisplayBrightness.lastError.length > 0 || DisplayBrightness.displays.length === 0 ? "Retry" : "Ready",
                "displays", DisplayBrightness.lastError.length > 0)
        if (KeyboardBrightness.ready || KeyboardBrightness.lastError.length > 0)
            add("keyboardBrightness", "󰌌", "Keyboard lighting", KeyboardBrightness.lastError
                    || detected(KeyboardBrightness.devices.length, "light"),
                KeyboardBrightness.lastError.length > 0 ? "Retry" : "Ready", "keyboardBrightness",
                KeyboardBrightness.lastError.length > 0)
        if (Bluetooth.available)
            add("bluetooth", "󰂯", "Bluetooth controller", Bluetooth.hardBlocked ? "Use your hardware radio switch"
                    : SafeText.singleLineText(Bluetooth.adapter.name || Bluetooth.adapter.adapterId, 128),
                Bluetooth.hardBlocked ? "Blocked" : Bluetooth.enabled ? "On" : "Off",
                // the Devices page lists controllers only when there is a choice to make
                Bluetooth.adapterCount > 1 ? "devices" : "", Bluetooth.hardBlocked)
        if (Network.hasWifiDevice)
            add("wifi", "󰤨", "Wi-Fi radio", Network.wifiHardBlocked ? "Use your hardware radio switch"
                    : Network.connectivityText || (Network.connected ? "Network connection available" : "No active connection"),
                Network.wifiHardBlocked ? "Blocked" : Network.wifiEnabled ? "On" : "Off", "", Network.wifiHardBlocked)
        return rows
    }

    function activate(action: string): void {
        if (action === "sound") Audio.openSoundSettings()
        else if (action === "devices") MenuState.setSettingsSection("devices")
        else if (action === "brightness") Brightness.retry()
        else if (action === "displays") DisplayBrightness.retry()
        else if (action === "keyboardBrightness") KeyboardBrightness.retry()
    }

    function copyReport(): void {
        if (_report.running) return
        root.copyState = "working"
        root.copyError = ""
        _report.running = true
    }

    function acceptReport(code: int, timedOut: bool, raw: string): void {
        try {
            if (code !== 0 || timedOut) throw new Error("Diagnostic report could not be collected. Run silere doctor in a terminal.")
            const report = JSON.parse(raw)
            if (!report || report.schemaVersion !== 1 || !report.runtime || !report.availability)
                throw new Error("Diagnostic report has an unsupported format.")
            report.devices = root.snapshot()
            Quickshell.clipboardText = JSON.stringify(report, null, 2)
            root.copyState = "done"
            _copiedHold.restart()
        } catch (error) {
            root.copyState = "failed"
            root.copyError = String(error.message || "Could not copy diagnostic report")
        }
    }

    // the same hold as the VPN address copy in Home
    readonly property Timer _copiedHoldTimer: Timer {
        id: _copiedHold
        interval: 1600
        onTriggered: if (root.copyState === "done") root.copyState = ""
    }

    BoundedProcess {
        id: _report
        timeoutMs: 20000
        // the snapshot below replaces the script's devices section, so it must not call back into this shell for one
        environment: ({ "SILERE_DOCTOR_LIVE": "0" })
        command: ["bash", Quickshell.shellDir + "/scripts/doctor.sh", "--json"]
        stdout: StdioCollector { id: _reportOut }
        onExited: code => root.acceptReport(code, timedOut, _reportOut.text)
    }

    IpcHandler {
        target: "diagnostics"
        function status(): string { return JSON.stringify(root.snapshot()) }
    }
}
