pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    readonly property bool toolAvailable: Networking.backend !== NetworkBackendType.None
    readonly property var _devices: Networking.devices.values || []
    readonly property bool _wanted: !Idle.isIdle && (
        ShellSettings.barShowNetwork
        || ShellSettings.updatesWidget
        || (ShellSettings.underlineGlow && ShellSettings.underlineNetGlow)
        || MenuState.open
        || QuickActionsState.open)
    readonly property bool monitoring: toolAvailable && _wanted

    readonly property var _linkState: {
        const devices = root._devices
        let best = null
        let hasWifi = false

        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (!device) continue

            const wifi = device.type === DeviceType.Wifi
            const wired = device.type === DeviceType.Wired
            if (wifi) hasWifi = true
            if (!wifi && !wired) continue

            let network = null
            if (wifi) {
                const networks = device.networks ? (device.networks.values || []) : []
                for (let j = 0; j < networks.length; j++) {
                    if (networks[j] && networks[j].connected) {
                        network = networks[j]
                        break
                    }
                }
            } else {
                network = device.network
            }

            const connected = device.connected || (network && network.connected)
            if (!connected) continue
            const priority = wifi ? 2 : 1
            if (!best || priority > best.priority)
                best = { device: device, network: network, wifi: wifi, priority: priority }
        }

        return { best: best, hasWifi: hasWifi }
    }

    readonly property bool available: toolAvailable && _devices.length > 0
    readonly property bool connected: _linkState.best !== null
    readonly property bool isWifi: connected && _linkState.best.wifi
    readonly property bool hasWifiDevice: _linkState.hasWifi
    readonly property string connectionName: {
        const best = _linkState.best
        return best && best.network ? (best.network.name || "") : ""
    }
    readonly property string deviceName: {
        const best = _linkState.best
        return best && best.device ? (best.device.name || "") : ""
    }
    readonly property string deviceType: connected ? (isWifi ? "wifi" : "ethernet") : ""
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property int signalStrength: {
        const best = _linkState.best
        if (!best || !best.wifi || !best.network) return 0
        return Math.round(Math.max(0, Math.min(1, best.network.signalStrength || 0)) * 100)
    }

    property bool hasVpn: false
    property string vpnName: ""

    function signalGlyph(s: int): string {
        return s > 75 ? "󰤨" : s > 50 ? "󰤥" : s > 25 ? "󰤢" : "󰤟"
    }

    readonly property string underlyingIcon: {
        if (!connected) return "󰤭"
        if (isWifi) return signalGlyph(signalStrength)
        return "󰈀"
    }

    readonly property string icon: {
        if (!connected) return "󰤭"
        if (hasVpn) return "󰦝"
        return underlyingIcon
    }

    function toggleWifi(): void {
        if (!toolAvailable || !hasWifiDevice) return
        Networking.wifiEnabled = !Networking.wifiEnabled
    }

    property bool _scannerWanted: false
    property string wifiConnecting: ""
    property string wifiError: ""
    property var _pendingNetwork: null
    readonly property bool wifiScanning: _scanWarmup.running
    readonly property bool wifiScanFailed: false

    function _setScannerEnabled(enabled: bool): void {
        const devices = root._devices
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (device && device.type === DeviceType.Wifi)
                device.scannerEnabled = enabled
        }
    }

    function scanWifi(forceRescan: bool): void {
        if (!toolAvailable || !wifiEnabled || !hasWifiDevice) {
            clearWifiScan()
            return
        }

        _scannerWanted = true
        if (forceRescan) {
            _setScannerEnabled(false)
            Qt.callLater(() => {
                if (root._scannerWanted) root._setScannerEnabled(true)
            })
        } else {
            _setScannerEnabled(true)
        }
        _scanWarmup.restart()
    }

    function clearWifiScan(): void {
        _scannerWanted = false
        _scanWarmup.stop()
        _setScannerEnabled(false)
        wifiError = ""
    }

    function clearWifiError(): void {
        if (wifiError.length > 0) wifiError = ""
    }

    function _wifiList(): var {
        if (!_scannerWanted) return []
        const bySsid = {}
        const order = []
        const devices = root._devices

        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (!device || device.type !== DeviceType.Wifi || !device.networks) continue
            const networks = device.networks.values || []
            for (let j = 0; j < networks.length; j++) {
                const network = networks[j]
                const ssid = network ? String(network.name || "") : ""
                if (!network || ssid.length === 0) continue
                const signal = Math.round(Math.max(0, Math.min(1, network.signalStrength || 0)) * 100)
                const existing = bySsid[ssid]
                if (existing) {
                    if (signal > existing.signal) {
                        existing.signal = signal
                        existing.ref = network
                    }
                    if (network.connected) existing.active = true
                    if (network.known) existing.known = true
                    continue
                }
                bySsid[ssid] = {
                    ssid: ssid,
                    signal: signal,
                    secured: network.security !== WifiSecurityType.Open,
                    active: network.connected,
                    known: network.known,
                    ref: network
                }
                order.push(ssid)
            }
        }

        order.sort((a, b) => {
            const A = bySsid[a]
            const B = bySsid[b]
            if (A.active !== B.active) return A.active ? -1 : 1
            return B.signal - A.signal
        })
        return order.map(ssid => bySsid[ssid])
    }

    readonly property var wifiNetworks: _wifiList()

    function _findWifiNetwork(ssid: string): var {
        const devices = root._devices
        let best = null
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (!device || device.type !== DeviceType.Wifi || !device.networks) continue
            const networks = device.networks.values || []
            for (let j = 0; j < networks.length; j++) {
                const network = networks[j]
                if (!network || network.name !== ssid) continue
                if (!best || network.signalStrength > best.signalStrength) best = network
            }
        }
        return best
    }

    function _finishWifi(success: bool): void {
        _connectTimeout.stop()
        if (!success && wifiConnecting.length > 0) wifiError = wifiConnecting
        else if (success) wifiError = ""
        wifiConnecting = ""
        _pendingNetwork = null
    }

    function connectWifi(ssid: string, password: string): void {
        if (!toolAvailable || ssid.length === 0) return
        const network = _findWifiNetwork(ssid)
        if (!network) {
            wifiError = ssid
            return
        }

        wifiError = ""
        wifiConnecting = ssid
        _pendingNetwork = network
        _connectTimeout.restart()
        if (password && password.length > 0) network.connectWithPsk(password)
        else network.connect()
    }

    function disconnectWifi(): void {
        const best = _linkState.best
        if (!best) return
        if (best.network) best.network.disconnect()
        else if (best.device) best.device.disconnect()
    }

    Connections {
        target: root._pendingNetwork
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (root._pendingNetwork && root._pendingNetwork.connected)
                root._finishWifi(true)
        }
        function onConnectionFailed() { root._finishWifi(false) }
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (!Networking.wifiEnabled) root.clearWifiScan()
        }
    }

    onHasWifiDeviceChanged: if (_scannerWanted) Qt.callLater(() => root._setScannerEnabled(true))

    Timer {
        id: _scanWarmup
        interval: 900
    }

    Timer {
        id: _connectTimeout
        interval: 20000
        onTriggered: root._finishWifi(false)
    }

    function _splitNmcliLine(line: string): var {
        const fields = []
        let cur = ""
        let escaped = false
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (escaped) { cur += ch; escaped = false }
            else if (ch === "\\") { escaped = true }
            else if (ch === ":") { fields.push(cur); cur = "" }
            else { cur += ch }
        }
        if (escaped) cur += "\\"
        fields.push(cur)
        return fields
    }

    function _queueVpnRefresh(): void {
        if (!SystemTools.hasNmcli || !_wanted || _vpnProc.running) return
        _vpnRefresh.restart()
    }

    readonly property string _linkSignature: {
        const devices = root._devices
        const parts = [String(Networking.wifiEnabled)]
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (!device) continue
            parts.push(`${device.type}:${device.name}:${device.connected}:${device.state}`)
            if (device.type !== DeviceType.Wifi || !device.networks) continue
            const networks = device.networks.values || []
            for (let j = 0; j < networks.length; j++) {
                const network = networks[j]
                if (network && (network.connected || network.stateChanging))
                    parts.push(`${network.name}:${network.connected}:${network.state}`)
            }
        }
        return parts.join("|")
    }

    on_LinkSignatureChanged: _queueVpnRefresh()
    on_WantedChanged: {
        if (_wanted) _queueVpnRefresh()
        else {
            _vpnRefresh.stop()
            root.clearWifiScan()
            root._resetTraffic()
        }
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._queueVpnRefresh() }
    }

    Timer {
        id: _vpnRefresh
        interval: 180
        onTriggered: _vpnProc.running = true
    }

    Process {
        id: _vpnProc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "TYPE,NAME", "connection", "show", "--active"]
        onRunningChanged: if (running) {
            root.hasVpn = false
            root.vpnName = ""
        }
        stdout: SplitParser {
            onRead: line => {
                if (root.hasVpn) return
                const fields = root._splitNmcliLine(line)
                if (fields.length >= 2
                        && (fields[0] === "vpn" || fields[0] === "wireguard" || fields[0] === "tun")) {
                    root.hasVpn = true
                    root.vpnName = fields.slice(1).join(":")
                }
            }
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: root._wanted && SystemTools.hasNmcli
        onTriggered: root._queueVpnRefresh()
    }

    property real downBps: 0
    property real upBps: 0
    property real _lastRxBytes: -1
    property real _lastTxBytes: -1
    property real _lastStatsMs: 0
    property bool _statsRefreshing: false

    readonly property bool statsDeviceReady: connected
        && deviceName.length > 0
        && deviceName.indexOf("/") < 0
        && deviceName.indexOf("..") < 0
    readonly property bool statsWanted: ShellSettings.barShowNetwork && ShellSettings.networkTrafficStats
    readonly property bool trafficActive: statsWanted && connected
        && (downBps >= 1024 || upBps >= 1024)
    readonly property string trafficLabel: "󰁅 " + formatRate(downBps) + " 󰁝 " + formatRate(upBps)

    function formatRate(bps: real): string {
        const value = Math.max(0, bps)
        if (value >= 1073741824)
            return (value / 1073741824).toFixed(value >= 10737418240 ? 0 : 1) + " GB/s"
        if (value >= 1048576)
            return (value / 1048576).toFixed(value >= 10485760 ? 0 : 1) + " MB/s"
        if (value >= 1024)
            return (value / 1024).toFixed(value >= 10240 ? 0 : 1) + " KB/s"
        return Math.round(value) + " B/s"
    }

    function _resetTraffic(): void {
        downBps = 0
        upBps = 0
        _lastRxBytes = -1
        _lastTxBytes = -1
        _lastStatsMs = 0
    }

    function _sampleTraffic(): void {
        if (!statsWanted || !statsDeviceReady || Idle.isIdle || _statsRefreshing) return
        _statsRefreshing = true
        try {
            _netDevFile.reload()
            if (!_netDevFile.waitForJob()) {
                _resetTraffic()
                return
            }

            const lines = (_netDevFile.text() || "").split(/\r?\n/)
            let rx = -1
            let tx = -1
            for (let i = 0; i < lines.length; i++) {
                const sep = lines[i].indexOf(":")
                if (sep < 0 || lines[i].slice(0, sep).trim() !== root.deviceName) continue
                const fields = lines[i].slice(sep + 1).trim().split(/\s+/)
                if (fields.length >= 9) {
                    rx = Number(fields[0])
                    tx = Number(fields[8])
                }
                break
            }
            if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) {
                _resetTraffic()
                return
            }

            const now = Date.now()
            const dt = (now - root._lastStatsMs) / 1000
            if (root._lastRxBytes >= 0 && root._lastTxBytes >= 0 && root._lastStatsMs > 0 && dt >= 0.2) {
                root.downBps = rx >= root._lastRxBytes ? (rx - root._lastRxBytes) / dt : 0
                root.upBps = tx >= root._lastTxBytes ? (tx - root._lastTxBytes) / dt : 0
            }
            root._lastRxBytes = rx
            root._lastTxBytes = tx
            root._lastStatsMs = now
        } finally {
            _statsRefreshing = false
        }
    }

    onDeviceNameChanged: {
        root._resetTraffic()
        if (_statsPoll.running) _statsPoll.restart()
    }

    FileView {
        id: _netDevFile
        path: root.statsWanted ? "/proc/net/dev" : ""
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    Timer {
        id: _statsPoll
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.statsWanted && root.statsDeviceReady && !Idle.isIdle
        onTriggered: root._sampleTraffic()
        onRunningChanged: if (!running) root._resetTraffic()
    }
}
