pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt

// thin event-driven wrapper over BlueZ DBus; adapter is null with no bluetoothd/radio (reads unavailable)
// namespaced import (Bt) so the bare name never clashes with this singleton
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

    // Battery % of the first connected device that reports one; -1 if none.
    readonly property int connectedBattery: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected && d.batteryAvailable)
                return Math.round(d.battery > 1 ? d.battery : d.battery * 100)
        }
        return -1
    }

    property var devices: []
    function _rebuildDevices(): void {
        const list = _devices.slice()
        list.sort((a, b) => {
            if (!a || !b) return 0
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired)       return a.paired ? -1 : 1
            const an = (a.deviceName || a.name || "").toLowerCase()
            const bn = (b.deviceName || b.name || "").toLowerCase()
            return an < bn ? -1 : (an > bn ? 1 : 0)
        })
        devices = list
    }
    on_DevicesChanged: _rebuildDevices()
    Component.onCompleted: _rebuildDevices()

    function toggle(): void {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    function setScan(on: bool): void {
        if (!adapter) return
        // discovering is a D-Bus proxy: re-asserting the current value fires a
        // redundant Start/StopDiscovery that bluez rejects. Only write on change.
        const want = on && adapter.enabled
        if (adapter.discovering !== want) adapter.discovering = want
    }

    // Dispatch by address through the raw _devices array so we always call
    // methods on the live C++ object, not a sorted JS copy that may lose binding.
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
