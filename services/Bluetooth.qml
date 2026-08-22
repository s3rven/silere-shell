pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt

Singleton {
    id: root

    readonly property var adapter: Bt.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled:   adapter ? adapter.enabled : false

    // Backend models can be momentarily empty while BlueZ re-enumerates.
    readonly property var _devices: (adapter && adapter.devices)
        ? (adapter.devices.values || []) : []

    readonly property int connectedCount: {
        let n = 0
        for (let i = 0; i < _devices.length; i++)
            if (_devices[i] && _devices[i].connected) n++
        return n
    }

    readonly property string connectedName: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected) return root.deviceLabel(d)
        }
        return ""
    }

    function deviceLabel(device): string {
        if (!device) return "Unknown"
        return SafeText.singleLineText(
            device.deviceName || device.name || device.address || "Unknown", 128) || "Unknown"
    }

    // BlueZ can briefly advertise batteryAvailable before the percentage
    // arrives. Keep the conversion and validation in one place so every UI
    // surface falls back to its non-battery label instead of showing NaN%.
    function batteryPercent(device): int {
        if (!device || !device.batteryAvailable) return -1
        const raw = Number(device.battery)
        if (!isFinite(raw) || raw < 0) return -1
        return Math.max(0, Math.min(100, Math.round(raw > 1 ? raw : raw * 100)))
    }

    readonly property int connectedBattery: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected) return root.batteryPercent(d)
        }
        return -1
    }

    readonly property var devices: {
        const list = _devices.slice()
        list.sort((a, b) => {
            if (!a || !b) return 0
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired)       return a.paired ? -1 : 1
            const an = (a.deviceName || a.name || "").toLowerCase()
            const bn = (b.deviceName || b.name || "").toLowerCase()
            return an < bn ? -1 : (an > bn ? 1 : 0)
        })
        return list
    }

    function toggle(): void {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    property bool _scanRequested: false
    function setScan(on: bool): void {
        const want = !!(on && adapter && adapter.enabled)
        // coalesce: onOpenChanged and Component.onCompleted can request the same state in one pass and BlueZ answers "Operation already in progress"
        _scanRequested = want
        if (!_scanSync.running) _scanSync.restart()
    }

    Timer {
        id: _scanSync
        interval: 0
        onTriggered: {
            if (!root.adapter) return
            const want = root._scanRequested && root.adapter.enabled
            if (root.adapter.discovering !== want) root.adapter.discovering = want
        }
    }

    // BlueZ signals a refused connect or pair only by dropping back to idle, so an attempt is tracked until it lands
    property string errorAddr: ""
    property string errorKind: ""
    property string _pendingAddr: ""
    property string _pendingKind: ""
    property bool   _pendingStarted: false
    // only undo pairable when this service raised it. An adapter already made pairable by the user or another tool belongs to that owner
    property var    _pairableAdapter: null

    readonly property var _pendingDevice: {
        if (root._pendingAddr === "") return null
        for (let i = 0; i < root._devices.length; i++) {
            const d = root._devices[i]
            if (d && d.address === root._pendingAddr) return d
        }
        return null
    }
    readonly property int  _pendingState:     root._pendingDevice ? root._pendingDevice.state : -1
    readonly property bool _pendingConnected: root._pendingDevice ? !!root._pendingDevice.connected : false
    readonly property bool _pendingPaired:    root._pendingDevice ? !!root._pendingDevice.paired : false
    readonly property bool _pendingPairing:   root._pendingDevice ? !!root._pendingDevice.pairing : false

    on_PendingStateChanged:     root._queueSettle()
    on_PendingConnectedChanged: root._queueSettle()
    on_PendingPairedChanged:    root._queueSettle()
    on_PendingPairingChanged:   root._queueSettle()

    // one BlueZ update moves several of these at once, and settling inside the change pass
    // re-enters _pendingState's own binding; coalesce to one settle after the pass
    property bool _settleQueued: false
    function _queueSettle(): void {
        if (root._settleQueued) return
        root._settleQueued = true
        Qt.callLater(root._settleNow)
    }

    function _settleNow(): void {
        root._settleQueued = false
        root._settlePending()
    }

    // started guards the gap before BlueZ moves the device, which would otherwise read as an instant failure
    function _attemptOutcome(kind: string, started: bool, connected: bool, paired: bool,
                             pairing: bool, state: int): string {
        if (kind === "pair") {
            if (paired) return "ok"
            if (pairing) return ""
            return started ? "failed" : ""
        }
        if (connected) return "ok"
        if (state === Bt.BluetoothDeviceState.Connecting) return ""
        return started ? "failed" : ""
    }

    function clearError(): void {
        root.errorAddr = ""
        root.errorKind = ""
    }

    // nothing watches an attempt once its list is gone, and the guard would still fire minutes later and paint a stale failure on the next open
    function abandonAttempt(): void {
        root._endAttempt()
        root.clearError()
    }

    function _beginAttempt(address: string, kind: string): void {
        root._armPairable(kind === "pair" ? root.adapter : null)
        root.clearError()
        root._pendingAddr = address
        root._pendingKind = kind
        root._pendingStarted = false
        _attemptGuard.restart()
    }

    function _armPairable(target): void {
        root._restorePairable()
        if (!target || target.pairable) return
        target.pairable = true
        root._pairableAdapter = target
    }

    function _restorePairable(): void {
        const owned = root._pairableAdapter
        root._pairableAdapter = null
        if (owned) owned.pairable = false
    }

    function _endAttempt(): void {
        _attemptGuard.stop()
        root._pendingAddr = ""
        root._pendingKind = ""
        root._pendingStarted = false
        root._restorePairable()
    }

    function _settlePending(): void {
        if (root._pendingAddr === "") return
        if (root._pendingKind === "pair") {
            if (root._pendingPairing) root._pendingStarted = true
        } else if (root._pendingState === Bt.BluetoothDeviceState.Connecting) {
            root._pendingStarted = true
        }

        const outcome = root._attemptOutcome(root._pendingKind, root._pendingStarted,
            root._pendingConnected, root._pendingPaired, root._pendingPairing, root._pendingState)
        if (outcome === "") return
        if (outcome === "failed") {
            root.errorAddr = root._pendingAddr
            root.errorKind = root._pendingKind
        }
        root._endAttempt()
    }

    // an attempt that never moves the device would otherwise hold the row on its in-progress label forever
    Timer {
        id: _attemptGuard
        interval: 20000
        onTriggered: {
            if (root._pendingAddr === "") return
            root.errorAddr = root._pendingAddr
            root.errorKind = root._pendingKind
            root._endAttempt()
        }
    }

    // dispatch by address through the raw _devices array to reach the live C++ object, not a sorted JS copy
    function connectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { root._beginAttempt(address, "connect"); d.connect(); return }
        }
    }
    function disconnectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { root._endAttempt(); root.clearError(); d.disconnect(); return }
        }
    }
    function pairDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { root._beginAttempt(address, "pair"); d.pair(); return }
        }
    }
    function cancelPair(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { root._endAttempt(); root.clearError(); d.cancelPair(); return }
        }
    }
}
