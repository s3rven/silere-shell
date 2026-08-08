pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt

Singleton {
    id: root

    readonly property var adapter: Bt.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled:   adapter ? adapter.enabled : false

    readonly property var _devices: (adapter && adapter.devices) ? adapter.devices.values : []

    readonly property int connectedCount: {
        let n = 0
        for (let i = 0; i < _devices.length; i++)
            if (_devices[i] && _devices[i].connected) n++
        return n
    }

    readonly property string connectedName: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected) return d.deviceName || d.name || ""
        }
        return ""
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

    // dispatch by address through the raw _devices array to reach the live C++ object, not a sorted JS copy
    function connectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.connect(); return }
        }
    }
    function disconnectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.disconnect(); return }
        }
    }
    function pairDevice(address: string): void {
        if (adapter) adapter.pairable = true
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.pair(); return }
        }
    }
    function cancelPair(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.cancelPair(); return }
        }
    }
}
