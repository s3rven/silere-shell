pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property bool available:        false
    property bool connected:        false
    property bool isWifi:           false
    property bool hasWifiDevice:    false   // any NM-managed wifi radio exists at all
    property bool hasVpn:           false
    property string connectionName: ""
    property string vpnName:        ""
    property string deviceName:     ""
    property string deviceType:     ""
    property bool monitoring:        false
    readonly property bool toolAvailable: SystemTools.hasNmcli
    readonly property bool _wanted: !Idle.isIdle && (
        ShellSettings.barShowNetwork
        || ShellSettings.updatesWidget
        || (ShellSettings.underlineGlow && ShellSettings.underlineNetGlow)
        || MenuState.open
        || QuickActionsState.open)
    property bool wifiEnabled:      true   // radio (rfkill) state, drives the quick toggle
    property var    wifiNetworks:   []     // picker list: [{ssid, signal, secured, active, known}]
    property string wifiConnecting: ""     // ssid mid-connect, "" when idle
    property string wifiError:      ""     // ssid that last failed to connect, cleared on retry
    property var    _savedWifi:     ({})   // ssid -> true for saved wifi connections
    property bool   _wifiScanRescan: false
    property bool   _pendingWifiRescan: false
    property bool   wifiScanFailed:  false
    readonly property bool wifiScanning: _savedProc.running || _wifiScanProc.running
    property bool   _refreshPending: false
    property int    _queryFailures: 0
    property bool   _statsRefreshing: false
    property int signalStrength:    0
    property real downBps:          0
    property real upBps:            0
    property real _lastRxBytes:     -1
    property real _lastTxBytes:     -1
    property real _lastStatsMs:     0

    readonly property bool statsDeviceReady: connected
        && deviceName.length > 0
        && deviceName.indexOf("/") < 0
        && deviceName.indexOf("..") < 0
    readonly property bool statsWanted: ShellSettings.barShowNetwork && ShellSettings.networkTrafficStats
    readonly property bool trafficActive: statsWanted
        && connected
        && deviceName.length > 0
        && (downBps >= 1024 || upBps >= 1024)
    // Nerd-font arrows, not ↓/↑: the typographic arrows render in the base
    // mono face and read as a different font next to the bar's icon glyphs.
    readonly property string trafficLabel: "󰁅 " + formatRate(downBps) + " 󰁝 " + formatRate(upBps)


    function signalGlyph(s: int): string {
        return s > 75 ? "󰤨" : s > 50 ? "󰤥" : s > 25 ? "󰤢" : "󰤟"
    }

    // The underlying link's icon, ignoring any VPN overlay ("VPN / wifi").
    readonly property string underlyingIcon: {
        if (!connected) return "󰤭"
        if (isWifi) return signalGlyph(signalStrength)
        return "󰈀"
    }

    readonly property string icon: {
        if (!connected) return "󰤭"
        if (hasVpn)     return "󰦝"
        return underlyingIcon
    }

    function refresh(): void {
        if (!toolAvailable || !root._wanted) return
        if (_proc.running) {
            _refreshPending = true
            return
        }
        _refreshPending = false
        _proc.running = true
    }

    function toggleWifi(): void {
        if (!toolAvailable || _radioSet.running) return
        _radioSet.exec(["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"])
    }

    function scanWifi(forceRescan: bool): void {
        if (!toolAvailable || !wifiEnabled) {
            clearWifiScan()
            return
        }
        if (forceRescan) _pendingWifiRescan = true
        _beginWifiScan()
    }

    function _beginWifiScan(): void {
        if (!toolAvailable || !wifiEnabled || _savedProc.running || _wifiScanProc.running) return
        wifiScanFailed = false
        _wifiScanRescan = _pendingWifiRescan
        _pendingWifiRescan = false
        _savedProc.running = true
    }

    function clearWifiScan(): void {
        wifiError = ""
        wifiScanFailed = false
        _wifiScanRescan = false
        _pendingWifiRescan = false
        if (wifiNetworks.length > 0) wifiNetworks = []
    }

    function clearWifiError(): void {
        if (wifiError.length > 0) wifiError = ""
    }

    function _sameWifiNetworks(a, b): bool {
        if (!a || !b || a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            const A = a[i]
            const B = b[i]
            if (!A || !B) return false
            if (A.ssid !== B.ssid || A.signal !== B.signal || A.secured !== B.secured
                    || A.active !== B.active || A.known !== B.known)
                return false
        }
        return true
    }

    // Empty password → relies on saved creds (known) or open network.
    function connectWifi(ssid: string, password: string): void {
        if (!toolAvailable || ssid.length === 0 || _wifiActProc.running) return
        root.wifiError = ""
        root.wifiConnecting = ssid
        const cmd = ["nmcli", "-w", "20", "device", "wifi", "connect", ssid]
        if (password && password.length > 0) { cmd.push("password"); cmd.push(password) }
        _wifiActProc.exec(cmd)
    }

    function disconnectWifi(): void {
        if (!toolAvailable || deviceName.length === 0 || _wifiActProc.running) return
        _wifiActProc.exec(["nmcli", "device", "disconnect", deviceName])
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

    function _isVpn(type: string): bool {
        return type === "tun" || type === "wireguard" || type === "vpn"
    }

    function _devicePriority(type: string): int {
        if (!type) return -1                  // blank/malformed type — never treat as the active link
        if (type === "wifi") return 4
        if (type === "ethernet") return 3
        if (_isVpn(type) || type === "loopback" || type === "lo") return -1
        return 1                              // other real device (mobile, tether…) — low but usable
    }

    function _resetTraffic(): void {
        downBps = 0
        upBps = 0
        _lastRxBytes = -1
        _lastTxBytes = -1
        _lastStatsMs = 0
    }

    function formatRate(bps: real): string {
        const v = Math.max(0, bps)
        if (v >= 1073741824)
            return (v / 1073741824).toFixed(v >= 10737418240 ? 0 : 1) + " GB/s"
        if (v >= 1048576)
            return (v / 1048576).toFixed(v >= 10485760 ? 0 : 1) + " MB/s"
        if (v >= 1024)
            return (v / 1024).toFixed(v >= 10240 ? 0 : 1) + " KB/s"
        return Math.round(v) + " B/s"
    }


    Component.onCompleted: _init()

    function _init(): void {
        if (!SystemTools.ready) return
        if (!toolAvailable) {
            _queryRetry.stop()
            _queryFailures = 0
            available = false
            connected = false
            deviceName = ""
            deviceType = ""
            hasWifiDevice = false
            wifiEnabled = false
            clearWifiScan()
            _resetTraffic()
            monitoring = false
            return
        }
        if (!root._wanted) {
            root._suspend()
            return
        }
        monitoring = true
        if (!_radioCheck.running) _radioCheck.running = true
        refresh()
    }

    function _suspend(): void {
        _queryRetry.stop()
        monitorDebounce.stop()
        _signalDebounce.stop()
        monitoring = false
        clearWifiScan()
        _resetTraffic()
    }

    on_WantedChanged: {
        if (!SystemTools.ready) return
        if (root._wanted) root._init()
        else root._suspend()
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._init() }
    }

    Process {
        id: _proc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "TYPE,DEVICE,STATE,CONNECTION", "device"]
        stdout: StdioCollector { id: _procOut }
        onExited: (code) => {
            if (code !== 0) {
                root._queryFailures++
                if (root._queryFailures < 3) _queryRetry.restart()
                else root.monitoring = false
                root.connected = false
                root.available = false
                root.isWifi = false
                root.connectionName = ""
                root.deviceName = ""
                root.deviceType = ""
                root.hasWifiDevice = false
                root.hasVpn = false
                root.vpnName = ""
                root.signalStrength = 0
                root._resetTraffic()
            } else {
                _queryRetry.stop()
                root._queryFailures = 0
                root.monitoring = root._wanted
                let best = null
                let vpn = false
                let vpnConn = ""
                let anyWifi = false
                const lines = (_procOut.text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const parts = root._splitNmcliLine(lines[i])
                    if (parts.length < 4) continue
                    const type = parts[0]
                    const device = parts[1]
                    const state = parts[2]
                    const conn = parts.slice(3).join(":")
                    if (type === "wifi" && !state.startsWith("unmanaged")) anyWifi = true
                    if (!state.startsWith("connected")) continue
                    if (root._isVpn(type)) { vpn = true; vpnConn = conn }
                    else {
                        const priority = root._devicePriority(type)
                        if (priority >= 0 && (!best || priority > best.priority))
                            best = { type: type, device: device, conn: conn, priority: priority }
                    }
                }
                root.hasWifiDevice = anyWifi
                const found = best !== null
                if (found) {
                    if (root.deviceName !== best.device) root._resetTraffic()
                    root.isWifi = (best.type === "wifi")
                    root.connectionName = best.conn
                    root.deviceName = best.device
                    root.deviceType = best.type
                }
                root.connected = found
                root.hasVpn = vpn
                root.vpnName = vpnConn
                root.available = true
                if (!found) {
                    root.isWifi = false
                    root.connectionName = ""
                    root.deviceName = ""
                    root.deviceType = ""
                    root.signalStrength = 0
                    root._resetTraffic()
                }
                if (root.isWifi && ShellSettings.barShowNetwork) _signalDebounce.restart()
                else root.signalStrength = 0
            }
            if (root._refreshPending) Qt.callLater(root.refresh)
        }
    }

    // Coalesces rapid nmcli events into a single signal scan
    Timer {
        id: _signalDebounce
        interval: 500
        onTriggered: {
            if (!root.toolAvailable || !root.isWifi || !ShellSettings.barShowNetwork || _signalProc.running) return
            _signalProc.running = true
        }
    }

    Connections {
        target: ShellSettings
        function onBarShowNetworkChanged() {
            if (ShellSettings.barShowNetwork && root.isWifi) _signalDebounce.restart()
            else root.signalStrength = 0
        }
    }

    Process {
        id: _signalProc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { id: _signalOut }
        onExited: (code) => {
            if (code !== 0) return
            const lines = (_signalOut.text || "").trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const parts = root._splitNmcliLine(lines[i])
                if (parts.length >= 2 && parts[0] === "*") {
                    root.signalStrength = parseInt(parts[1]) || 0
                    return
                }
            }
            root.signalStrength = 0
        }
    }

    // wi-fi radio state, refreshed on every nmcli event so external toggles (rfkill, airplane mode) stay in sync
    Process {
        id: _radioCheck
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "radio", "wifi"]
        stdout: StdioCollector { id: _radioOut }
        onExited: (code) => { if (code === 0) root.wifiEnabled = (_radioOut.text || "").trim() === "enabled" }
    }

    onWifiEnabledChanged: if (!wifiEnabled) clearWifiScan()

    // Fire-and-forget radio setter; re-reads radio state and device list once done.
    Process {
        id: _radioSet
        environment: ({ "LC_ALL": "C" })
        onExited: {
            if (root._wanted && !_radioCheck.running) _radioCheck.running = true
            root.refresh()
        }
    }

    // Saved wifi connection names → known-network flag. Chains into the scan.
    Process {
        id: _savedProc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector { id: _savedOut }
        onExited: {
            const set = {}
            const lines = (_savedOut.text || "").trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const p = root._splitNmcliLine(lines[i])
                if (p.length >= 2 && p[1].indexOf("wireless") >= 0) set[p[0]] = true
            }
            root._savedWifi = set
            if (root.toolAvailable && root.wifiEnabled && !_wifiScanProc.running) {
                root._wifiScanRescan = root._wifiScanRescan || root._pendingWifiRescan
                root._pendingWifiRescan = false
                _wifiScanProc.running = true
            } else {
                root.clearWifiScan()
            }
        }
    }

    // Visible access points, deduped by SSID (strongest signal wins).
    Process {
        id: _wifiScanProc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", root._wifiScanRescan ? "yes" : "no"]
        stdout: StdioCollector { id: _wifiScanOut }
        onExited: (code) => {
            root._wifiScanRescan = false
            if (code !== 0 || !root.toolAvailable || !root.wifiEnabled) {
                if (root.toolAvailable && root.wifiEnabled) {
                    root.wifiScanFailed = true
                    if (root.wifiNetworks.length > 0) root.wifiNetworks = []
                } else {
                    root.clearWifiScan()
                }
                return
            }
            root.wifiScanFailed = false
            const bySsid = {}
            const order = []
            const lines = (_wifiScanOut.text || "").trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].length === 0) continue
                const p = root._splitNmcliLine(lines[i])
                if (p.length < 4) continue
                const ssid = p[1]
                if (ssid.length === 0) continue        // hidden network
                const sig = parseInt(p[2]) || 0
                const sec = p[3].length > 0
                const act = p[0] === "yes"
                const ex = bySsid[ssid]
                if (ex) {
                    if (sig > ex.signal) ex.signal = sig
                    if (act) ex.active = true
                } else {
                    bySsid[ssid] = { ssid: ssid, signal: sig, secured: sec, active: act,
                                     known: root._savedWifi[ssid] === true }
                    order.push(ssid)
                }
            }
            order.sort((a, b) => {
                const A = bySsid[a], B = bySsid[b]
                if (A.active !== B.active) return A.active ? -1 : 1
                return B.signal - A.signal
            })
            const out = []
            for (let i = 0; i < order.length; i++) out.push(bySsid[order[i]])
            // identical scan → keep the old array; a reassign rebuilds every delegate and wipes in-progress password entry
            if (!root._sameWifiNetworks(out, root.wifiNetworks))
                root.wifiNetworks = out
            if (root._pendingWifiRescan) root._beginWifiScan()
        }
    }

    // shared connect/disconnect runner; WifiList's rescan timer handles re-scanning while the picker's open
    Process {
        id: _wifiActProc
        environment: ({ "LC_ALL": "C" })
        onExited: (code) => {
            if (code !== 0 && root.wifiConnecting.length > 0)
                root.wifiError = root.wifiConnecting
            root.wifiConnecting = ""
            root.refresh()
        }
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
        running: root.statsWanted && root.statsDeviceReady
            && !Idle.isIdle
        onTriggered: root._sampleTraffic()
        onRunningChanged: if (!running) root._resetTraffic()
    }

    SupervisedProcess {
        id: monitorProc
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "monitor"]
        superviseWhen: root.toolAvailable && root._wanted && root.monitoring
        restartDelay: 3000
        maxRestartDelay: 60000
        cleanExitOnly: true
        stdout: SplitParser { onRead: monitorDebounce.restart() }
        onRunningChanged: { if (running) root.refresh() }
        onGaveUpChanged: if (gaveUp) root.monitoring = false
    }

    Timer {
        id: monitorDebounce
        interval: 80
        onTriggered: {
            if (!_radioCheck.running) _radioCheck.running = true
            root.refresh()
        }
    }
    Timer {
        id: _queryRetry
        interval: Math.min(30000, 3000 * Math.pow(2, Math.max(0, root._queryFailures - 1)))
        onTriggered: root.refresh()
    }
    Timer {
        id: _fallbackPoll
        interval: root.monitoring || root._queryFailures >= 3 ? 300000 : 30000
        running: root.toolAvailable && root._wanted
        repeat: true
        onTriggered: root.refresh()
    }
}
