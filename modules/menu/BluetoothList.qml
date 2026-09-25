pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth as Bt
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    // the card only reaches its direct children, so whoever places this list says whether
    // its last row sits on the card's bottom corner
    property real lastRowRadius: 0

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _armedAddr: ""
    property string _forgetAddr: ""
    property real _armedAtMs: 0
    property real _forgetAtMs: 0
    Timer {
        id: _disarmTimer
        interval: 3000
        onTriggered: { root._armedAddr = ""; root._forgetAddr = "" }
    }

    property bool _searchLapsed: false
    Timer {
        interval: 10000
        running: root.open && Bluetooth.available && Bluetooth.enabled
            && Bluetooth.devices.length === 0 && !Idle.isIdle
        onRunningChanged: if (running) root._searchLapsed = false
        onTriggered: root._searchLapsed = true
    }

    function _syncScanState(): void {
        Bluetooth.setScan(root.open && Bluetooth.available && Bluetooth.enabled && !Idle.isIdle)
        if (!Bluetooth.available || !Bluetooth.enabled) {
            _disarmTimer.stop()
            root._armedAddr = ""
            Bluetooth.abandonAttempt()
        }
    }

    onOpenChanged: {
        _syncScanState()
        if (!open) { _disarmTimer.stop(); root._armedAddr = ""; Bluetooth.abandonAttempt() }
    }
    Component.onCompleted: _syncScanState()
    Component.onDestruction: {
        Bluetooth.setScan(false)
        Bluetooth.abandonAttempt()
    }

    Connections {
        target: Bluetooth
        function onAvailableChanged() { root._syncScanState() }
        function onEnabledChanged() { root._syncScanState() }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { root._syncScanState() }
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        ShellText {
            visible: root.open && (!Bluetooth.available || !Bluetooth.enabled || Bluetooth.devices.length === 0)
            width: parent.width
            height: 4 * Math.ceil(Math.max(Metrics.rowHeightFor(32), contentHeight + 16) / 4)
            leftPadding: 14
            rightPadding: 14
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: !Bluetooth.available ? "Bluetooth unavailable"
                : Bluetooth.hardBlocked ? "Blocked by the hardware switch"
                : !Bluetooth.enabled   ? "Bluetooth is off"
                : root._searchLapsed   ? "No devices found"
                :                        "Searching for devices…"
            color: Theme.menuTextDetail
            font.pixelSize: Settings.fontLabel
        }

        ShellListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            interactive: contentHeight > height
            spacing: 0
            // every visible value comes from the device or service; the delegate
            // owns no row state, so off-screen instances are safe to recycle
            reuseItems: true
            model: root.open ? Bluetooth.devices : []

            delegate: InlineOptionRow {
                id: _row
                required property var modelData
                required property int index
                width: _list.width
                bottomRadius: _row.index === _list.count - 1 ? root.lastRowRadius : 0

                readonly property bool   _armed: root._armedAddr === modelData.address && modelData.connected
                readonly property bool   _forgetArmed: root._forgetAddr === modelData.address
                readonly property bool   _failed: Bluetooth.errorAddr === modelData.address
                readonly property int _batt: Bluetooth.batteryPercent(modelData)
                readonly property string _state:
                    _forgetArmed ? "Forget?"
                    : _armed ? "Disconnect?"
                    : modelData.pairing ? "Cancel?"
                    : modelData.state === Bt.BluetoothDeviceState.Connecting    ? "Connecting…"
                    : modelData.state === Bt.BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : modelData.connected ? (_batt >= 0 ? _batt + "%" : "Connected")
                    : _row._failed ? (Bluetooth.errorKind === "pair" ? "Pairing failed" : "Failed")
                    : modelData.paired    ? "Paired"
                    : "Pair"

                glyph: Bluetooth.deviceGlyph(modelData.icon)
                label: Bluetooth.deviceLabel(modelData)
                status: _state
                selected: modelData.connected
                warning: _armed || _forgetArmed || modelData.pairing
                failed:  _failed

                function _activate(): void {
                    const addr = modelData.address
                    if (root._forgetAddr === addr) {
                        root._forgetAddr = ""
                        _disarmTimer.stop()
                    }
                    if (modelData.pairing) {
                        Bluetooth.cancelPair(addr)
                    } else if (modelData.connected) {
                        if (root._armedAddr === addr) {
                            // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
                            if (Date.now() - root._armedAtMs < Metrics.confirmGuardMs) return
                            root._armedAddr = ""
                            _disarmTimer.stop()
                            Bluetooth.disconnectDevice(addr)
                        } else {
                            root._armedAddr = addr
                            root._armedAtMs = Date.now()
                            _disarmTimer.restart()
                        }
                    } else if (modelData.paired) {
                        Bluetooth.connectDevice(addr)
                    } else {
                        Bluetooth.pairDevice(addr)
                    }
                }
                onTriggered: _activate()

                // right- or middle-click forgets a paired device; the first press only arms it
                function _forgetTap(): void {
                    if (!modelData.paired || modelData.connected) return
                    const addr = modelData.address
                    if (root._forgetAddr === addr) {
                        if (Date.now() - root._forgetAtMs < Metrics.confirmGuardMs) return
                        root._forgetAddr = ""
                        _disarmTimer.stop()
                        Bluetooth.forgetDevice(addr)
                    } else {
                        root._forgetAddr = addr
                        root._forgetAtMs = Date.now()
                        _disarmTimer.restart()
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton | Qt.MiddleButton
                    onTapped: _row._forgetTap()
                }
            }
        }
    }

    // the card's own divider sits in this gutter one px past the list: land the cue on it
    ListEdgeLines {
        x: 14; y: _col.y + _list.y
        width: Math.max(0, parent.width - 28); height: _list.height + 1
        visible: _list.visible
        list: _list
    }
}
