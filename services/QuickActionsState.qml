pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property bool barBottom: false
    property ShellScreen triggerScreen: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }
    onAnchorSourceChanged: if (open && anchorSource === null) close()

    function toggleAt(x: real, screen, bottom: bool, source): void {
        if (open) { close(); return }
        anchorX = x
        anchorSource = source ?? null
        barBottom = bottom
        triggerScreen = screen ?? null
        open = true
    }
    function close(): void {
        if (open) open = false
        anchorSource = null
        triggerScreen = null
    }

    IpcHandler {
        target: "quickActions"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.triggerScreen = null
            root.anchorSource = null
            root.barBottom = Metrics.barAtBottom
            root.open = true
        }
        function close(): void { root.close() }
    }

    // a hard-blocked radio refuses every write, so a row offering it would re-issue
    // two doomed requests per tap and never change
    readonly property bool wifiControllable: Network.toolAvailable && Network.hasWifiDevice
        && !Network.wifiHardBlocked
    readonly property bool btControllable: Bluetooth.available
    readonly property bool airplaneAvailable: wifiControllable || btControllable
    readonly property bool radiosOn: (wifiControllable && Network.wifiEnabled)
        || (btControllable && Bluetooth.enabled)

    property bool _airplaneLatched: false
    property bool _priorWifi: false
    property bool _priorBt: false

    // with nothing latched there is no prior state to honour, so both come back
    function _airplaneRestore(latched: bool, priorWifi: bool, priorBt: bool): var {
        return latched ? { wifi: priorWifi, bt: priorBt } : { wifi: true, bt: true }
    }

    function toggleAirplane(): void {
        if (radiosOn) {
            _priorWifi = wifiControllable && Network.wifiEnabled
            _priorBt = btControllable && Bluetooth.enabled
            _airplaneLatched = true
            if (_priorWifi) Network.toggleWifi()
            if (_priorBt) Bluetooth.toggle()
            return
        }
        const want = _airplaneRestore(_airplaneLatched, _priorWifi, _priorBt)
        _airplaneLatched = false
        if (wifiControllable && want.wifi && !Network.wifiEnabled) Network.toggleWifi()
        if (btControllable && want.bt && !Bluetooth.enabled) Bluetooth.toggle()
    }
}
