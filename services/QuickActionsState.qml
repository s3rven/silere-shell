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
    // a destroyed widget nulls this with no assignment behind it. Reordering bar widgets
    // hands the zone's Repeater a new array, which rebuilds every delegate, so the anchor
    // drops for a turn and comes straight back; only a bar that really went never returns.
    property bool _anchorWriting: false
    function _setAnchor(source): void {
        _anchorRegrab.stop()
        root._anchorWriting = true
        root.anchorSource = source ?? null
        root._anchorWriting = false
    }
    // claimed by whichever live widget asks first, not by the one being rebuilt: a zone's
    // Repeater creates the replacements before it destroys the originals, and the
    // destruction is deferred, so an edge-triggered handover lands on a dying instance
    function adoptAnchor(source): void {
        if (!root.open || !source) return
        if (root._anchorWriting || root.anchorSource !== null) return
        root._setAnchor(source)
    }
    onAnchorSourceChanged: {
        if (anchorSource !== null) { _anchorRegrab.stop(); return }
        if (root._anchorWriting || !root.open) return
        _anchorRegrab.restart()
    }
    // never expose this timer's state: a consumer that reacts by taking the anchor stops
    // the very timer it is bound to, which is a binding loop
    Timer {
        id: _anchorRegrab
        interval: 150
        onTriggered: if (root.open && root.anchorSource === null) root.close()
    }

    function toggleAt(x: real, screen, bottom: bool, source): void {
        if (open) { close(); return }
        anchorX = x
        _setAnchor(source)
        barBottom = bottom
        triggerScreen = screen ?? null
        open = true
    }
    function close(): void {
        // open first: clearing anchorSource while open re-enters close() through its handler
        if (open) open = false
        triggerScreen = null
        _setAnchor(null)
    }

    IpcHandler {
        target: "quickActions"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.triggerScreen = null
            root._setAnchor(null)
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
