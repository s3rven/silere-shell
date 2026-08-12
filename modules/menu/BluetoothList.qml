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

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _armedAddr: ""
    Timer { id: _disarmTimer; interval: 3000; onTriggered: root._armedAddr = "" }

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
        }
    }

    onOpenChanged: {
        _syncScanState()
        if (!open) { _disarmTimer.stop(); root._armedAddr = "" }
    }
    Component.onCompleted: _syncScanState()
    Component.onDestruction: Bluetooth.setScan(false)

    Connections {
        target: Bluetooth
        function onAvailableChanged() { root._syncScanState() }
        function onEnabledChanged() { root._syncScanState() }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { root._syncScanState() }
    }

    function _devGlyph(icon): string {
        const s = (icon || "").toLowerCase()
        if (s.indexOf("headset") >= 0 || s.indexOf("headphone") >= 0 || s.indexOf("audio") >= 0) return "󰋋"
        if (s.indexOf("mouse") >= 0)    return "󰍽"
        if (s.indexOf("keyboard") >= 0) return "󰌌"
        if (s.indexOf("phone") >= 0)    return "󰏳"
        if (s.indexOf("speaker") >= 0)  return "󰓃"
        if (s.indexOf("watch") >= 0)    return "󰖉"
        return "󰂱"
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0
        topPadding: 2
        bottomPadding: 2

        ShellText {
            visible: root.open && (!Bluetooth.available || !Bluetooth.enabled || Bluetooth.devices.length === 0)
            width: parent.width
            height: Metrics.rowHeightFor(32)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: !Bluetooth.available ? "Bluetooth unavailable"
                : !Bluetooth.enabled   ? "Bluetooth is off"
                : root._searchLapsed   ? "No devices found"
                :                        "Searching for devices…"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.pixelSize: Settings.fontLabel
        }

        ShellListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            interactive: contentHeight > height
            spacing: 0
            model: root.open ? Bluetooth.devices : []

            delegate: InlineOptionRow {
                id: _row
                required property var modelData
                required property int index
                width: _list.width

                readonly property bool   _armed: root._armedAddr === modelData.address && modelData.connected
                readonly property int _batt: Bluetooth.batteryPercent(modelData)
                readonly property string _state:
                    _armed ? "Disconnect?"
                    : modelData.pairing ? "Cancel?"
                    : modelData.state === Bt.BluetoothDeviceState.Connecting    ? "Connecting…"
                    : modelData.state === Bt.BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : modelData.connected ? (_batt >= 0 ? _batt + "%" : "Connected")
                    : modelData.paired    ? "Paired"
                    : "Pair"

                glyph: root._devGlyph(modelData.icon)
                label: Bluetooth.deviceLabel(modelData)
                status: _state
                selected: modelData.connected
                warning: _armed || modelData.pairing

                function _activate(): void {
                    const addr = modelData.address
                    if (modelData.pairing) {
                        Bluetooth.cancelPair(addr)
                    } else if (modelData.connected) {
                        if (root._armedAddr === addr) {
                            root._armedAddr = ""
                            _disarmTimer.stop()
                            Bluetooth.disconnectDevice(addr)
                        } else {
                            root._armedAddr = addr
                            _disarmTimer.restart()
                        }
                    } else if (modelData.paired) {
                        Bluetooth.connectDevice(addr)
                    } else {
                        Bluetooth.pairDevice(addr)
                    }
                }
                onTriggered: _activate()
            }
        }
    }

    ListEdgeLines {
        x: 0; y: _col.y + _list.y
        width: parent.width; height: _list.height
        visible: _list.visible
        list: _list
    }
}
