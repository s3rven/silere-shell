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

    // NetworkManager routes over a live wired link before Wi-Fi, so ranking Wi-Fi first named
    // the idle interface on a docked laptop and sampled it for the traffic readout.
    // hasLink is wired-only and absent on other backends: unknown counts as up.
    function _linkPriority(wired: bool, hasLink): int {
        if (!wired) return 2
        return hasLink === false ? 1 : 3
    }

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
            const priority = root._linkPriority(wired, device.hasLink)
            if (!best || priority > best.priority)
                best = { device: device, network: network, wifi: wifi, priority: priority }
        }

        return { best: best, hasWifi: hasWifi }
    }

    readonly property bool _rawAvailable: toolAvailable && _devices.length > 0
    // the device model empties for a frame while NetworkManager re-enumerates (vpn up/down, resume)
    property bool available: false
    on_RawAvailableChanged: {
        if (root._rawAvailable) { _availableGrace.stop(); root.available = true }
        else if (root.available) _availableGrace.restart()
    }
    Timer {
        id: _availableGrace
        interval: 2500
        onTriggered: root.available = root._rawAvailable
    }
    Component.onCompleted: root.available = root._rawAvailable
    readonly property bool connected: _linkState.best !== null
    readonly property bool isWifi: connected && _linkState.best.wifi
    readonly property bool hasWifiDevice: _linkState.hasWifi
    readonly property string connectionName: {
        const best = _linkState.best
        return best && best.network
            ? SafeText.singleLineText(best.network.name, 128) : ""
    }
    readonly property string deviceName: {
        const best = _linkState.best
        return best && best.device ? (best.device.name || "") : ""
    }
    readonly property string deviceType: connected ? (isWifi ? "wifi" : "ethernet") : ""
    readonly property bool wifiEnabled: Networking.wifiEnabled
    // rfkill's hard block: the radio cannot come back until the hardware switch does,
    // so writing wifiEnabled is refused and every retry looks like nothing happening
    readonly property bool wifiHardBlocked: toolAvailable && hasWifiDevice
        && !Networking.wifiHardwareEnabled
    readonly property int signalStrength: {
        const best = _linkState.best
        if (!best || !best.wifi || !best.network) return 0
        return Math.round(Math.max(0, Math.min(1, best.network.signalStrength || 0)) * 100)
    }

    property var _vpnState: ({ active: false, name: "" })
    readonly property bool hasVpn: _vpnState.active === true
    readonly property string vpnName: _vpnState.name || ""
    property bool _vpnCandidateActive: false
    property string _vpnCandidateName: ""
    property bool _vpnRefreshPending: false
    readonly property bool _vpnWanted: !Idle.isIdle && available
        && ShellSettings.barShowNetwork && SystemTools.hasNmcli

    function signalTier(s: int): int {
        return s > 75 ? 3 : s > 50 ? 2 : s > 25 ? 1 : 0
    }

    function signalGlyph(s: int): string {
        return ["󰤟", "󰤢", "󰤥", "󰤨"][signalTier(s)]
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
        if (!toolAvailable || !hasWifiDevice || wifiHardBlocked) return
        Networking.wifiEnabled = !Networking.wifiEnabled
    }

    property bool _scannerWanted: false
    property string wifiConnecting: ""
    property string wifiError: ""
    property int wifiErrorReason: ConnectionFailReason.Unknown
    // the saved profile's key is the thing that is wrong, so the row has to offer a retype
    readonly property bool wifiErrorNeedsSecret: wifiError.length > 0
        && (wifiErrorReason === ConnectionFailReason.NoSecrets
            || wifiErrorReason === ConnectionFailReason.WifiAuthTimeout)
    property var _pendingNetwork: null
    readonly property bool wifiScanning: _scanWarmup.running

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
        wifiErrorReason = ConnectionFailReason.Unknown
    }

    function clearWifiError(): void {
        if (wifiError.length > 0) wifiError = ""
        wifiErrorReason = ConnectionFailReason.Unknown
    }

    function _wifiList(): var {
        if (!_scannerWanted) return []
        // SSIDs are external strings: a normal object loses names such as
        // "constructor" and lets "__proto__" alter the lookup prototype.
        const bySsid = Object.create(null)
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
                    label: SafeText.singleLineText(ssid, 128) || "Unnamed network",
                    signal: signal,
                    secured: network.security !== WifiSecurityType.Open,
                    active: network.connected,
                    known: network.known,
                    ref: network
                }
                order.push(ssid)
            }
        }

        // by the tier the row draws, not the raw percentage: signal drifts a few points
        // between scans and neighbouring networks traded places under the pointer
        order.sort((a, b) => {
            const A = bySsid[a]
            const B = bySsid[b]
            if (A.active !== B.active) return A.active ? -1 : 1
            const tier = signalTier(B.signal) - signalTier(A.signal)
            return tier !== 0 ? tier : A.ssid.localeCompare(B.ssid)
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

    function _finishWifi(success: bool, reason: int): void {
        _connectTimeout.stop()
        if (!success && wifiConnecting.length > 0) {
            wifiError = wifiConnecting
            wifiErrorReason = reason
        } else if (success) {
            wifiError = ""
            wifiErrorReason = ConnectionFailReason.Unknown
        }
        wifiConnecting = ""
        _pendingNetwork = null
    }

    // Disabling Wi-Fi tears down the backend-side request. Clear our local
    // request too, otherwise its timeout reports a stale failure after Wi-Fi
    // has already been turned off.
    function _cancelWifiConnect(): void {
        _connectTimeout.stop()
        wifiConnecting = ""
        wifiErrorReason = ConnectionFailReason.Unknown
        _pendingNetwork = null
    }

    function connectWifi(ssid: string, password: string): void {
        if (!toolAvailable || ssid.length === 0) return
        const network = _findWifiNetwork(ssid)
        if (!network) {
            wifiError = ssid
            wifiErrorReason = ConnectionFailReason.Unknown
            return
        }

        wifiError = ""
        wifiErrorReason = ConnectionFailReason.Unknown
        wifiConnecting = ssid
        _pendingNetwork = network
        _connectTimeout.restart()
        if (password && password.length > 0) network.connectWithPsk(password)
        else network.connect()
    }

    // the active link can be the wired one, so this cannot go through _linkState.best
    function disconnectWifi(): void {
        const devices = root._devices
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i]
            if (!device || device.type !== DeviceType.Wifi) continue
            const networks = device.networks ? (device.networks.values || []) : []
            for (let j = 0; j < networks.length; j++)
                if (networks[j] && networks[j].connected) { networks[j].disconnect(); return }
            if (device.connected) { device.disconnect(); return }
        }
    }

    Connections {
        target: root._pendingNetwork
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (root._pendingNetwork && root._pendingNetwork.connected)
                root._finishWifi(true, ConnectionFailReason.Unknown)
        }
        function onConnectionFailed(reason) { root._finishWifi(false, reason) }
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (!Networking.wifiEnabled) {
                root.clearWifiScan()
                root._cancelWifiConnect()
            }
        }
    }

    onHasWifiDeviceChanged: {
        if (!root.hasWifiDevice) root._cancelWifiConnect()
        else if (_scannerWanted) Qt.callLater(() => root._setScannerEnabled(true))
    }

    Timer {
        id: _scanWarmup
        interval: 900
    }

    Timer {
        id: _connectTimeout
        interval: 20000
        onTriggered: root._finishWifi(false, ConnectionFailReason.Unknown)
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
        if (!root._vpnWanted) return
        if (_vpnProc.running) {
            root._vpnRefreshPending = true
            return
        }
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

    on_LinkSignatureChanged: {
        root._queueVpnRefresh()
        if (root.wifiError.length === 0) return
        const network = root._findWifiNetwork(root.wifiError)
        if (network && network.connected) root.clearWifiError()
    }
    on_VpnWantedChanged: {
        if (_vpnWanted) _queueVpnRefresh()
        else {
            _vpnRefresh.stop()
            _vpnRefreshPending = false
            _vpnProc.running = false
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

    BoundedProcess {
        id: _vpnProc
        timeoutMs: 15000
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "TYPE,NAME", "connection", "show", "--active"]
        onRunningChanged: if (running) {
            root._vpnCandidateActive = false
            root._vpnCandidateName = ""
        }
        stdout: SplitParser {
            onRead: line => {
                if (root._vpnCandidateActive) return
                const fields = root._splitNmcliLine(line)
                if (fields.length >= 2
                        && (fields[0] === "vpn" || fields[0] === "wireguard" || fields[0] === "tun")) {
                    root._vpnCandidateActive = true
                    root._vpnCandidateName = SafeText.singleLineText(
                        fields.slice(1).join(":"), 128)
                }
            }
        }
        onExited: (code) => {
            // hold the last known state through transient nmcli failures and publish one coherent update
            if (code === 0 && (root.hasVpn !== root._vpnCandidateActive
                    || root.vpnName !== root._vpnCandidateName)) {
                root._vpnState = {
                    active: root._vpnCandidateActive,
                    name: root._vpnCandidateName
                }
            }
            const refreshAgain = root._vpnRefreshPending && root._vpnWanted
            root._vpnRefreshPending = false
            if (refreshAgain) _vpnRefresh.restart()
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: root._vpnWanted
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
    property bool _trafficLatch: false
    readonly property bool trafficActive: statsWanted && connected && _trafficLatch
    readonly property string trafficLabel: "󰁅 " + formatRate(downBps) + " 󰁝 " + formatRate(upBps)

    // a bare threshold flaps the label in and out every tick on idle browsing
    function _updateTrafficLatch(): void {
        const peak = Math.max(root.downBps, root.upBps)
        if (peak >= 2048) root._trafficLatch = true
        else if (peak < 512) root._trafficLatch = false
    }

    // fixed columns in the bar's monospace font: a variable-width readout re-animates the pill every tick
    function formatRate(bps: real): string {
        const value = Math.max(0, bps)
        let n = value
        let unit = "B/s"
        if (value >= 1073741824)   { n = value / 1073741824; unit = "GB/s" }
        else if (value >= 1048576) { n = value / 1048576;    unit = "MB/s" }
        else if (value >= 1024)    { n = value / 1024;       unit = "KB/s" }
        const text = (n >= 100 || unit === "B/s") ? String(Math.round(n)) : n.toFixed(1)
        return ("    " + text).slice(-4) + " " + (unit + " ").slice(0, 4)
    }

    function _resetTraffic(): void {
        downBps = 0
        upBps = 0
        _lastRxBytes = -1
        _lastTxBytes = -1
        _lastStatsMs = 0
        _statsRefreshing = false
        _trafficLatch = false
    }

    // no in-flight guard: a reload that never reports back would wedge the poll for the session
    function _sampleTraffic(): void {
        if (!statsWanted || !statsDeviceReady || Idle.isIdle || OverviewState.active) return
        _statsRefreshing = true
        _netDevFile.reload()
    }

    function _applyTrafficSample(raw: string): void {
        if (!_statsRefreshing) return
        try {
            const lines = (raw || "").split(/\r?\n/)
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
                root._updateTrafficLatch()
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
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._statsRefreshing)
            root._applyTrafficSample(_netDevFile.text())
        onLoadFailed: if (root._statsRefreshing) root._resetTraffic()
    }

    Timer {
        id: _statsPoll
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.statsWanted && root.statsDeviceReady
            && !Idle.isIdle && !OverviewState.active
        onTriggered: root._sampleTraffic()
        onRunningChanged: if (!running) root._resetTraffic()
    }
}
