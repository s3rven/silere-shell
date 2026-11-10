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
    // the card only reaches its direct children, so whoever places this list says whether its last row sits on the card's bottom corner
    property real lastRowRadius: 0

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    readonly property ArmConfirm _confirm: ArmConfirm {}

    property bool _searchLapsed: false
    Timer {
        interval: 10000
        running: root.open && Bluetooth.available && Bluetooth.enabled
            && Bluetooth.devices.length === 0 && !Idle.isIdle
        onRunningChanged: if (running) root._searchLapsed = false
        onTriggered: root._searchLapsed = true
    }

    function _syncScanState(): void {
        Bluetooth.requestScan(root, root.open && Bluetooth.available && Bluetooth.enabled && !Idle.isIdle)
        if (!Bluetooth.available || !Bluetooth.enabled) root._confirm.clear()
    }

    onOpenChanged: {
        _syncScanState()
        if (!open) root._confirm.clear()
    }
    Component.onCompleted: _syncScanState()
    Component.onDestruction: {
        Bluetooth.requestScan(root, false)
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

        SelectRow {
            visible: root.open && Bluetooth.adapterCount > 1
            glyph: "󰂯"
            label: "Controller"
            description: "Applies to this session"
            model: Bluetooth.adapterChoices
            currentValue: Bluetooth.adapterChoice
            onChosen: value => Bluetooth.selectAdapter(String(value))
        }

        InlineOptionRow {
            visible: root.open
            glyph: "󰌌"
            label: "Pair with a passkey"
            status: Settings.bluetoothSettingsCommand.length > 0 ? "Open manager" : "Needs blueman"
            interactive: Settings.bluetoothSettingsCommand.length > 0
            onTriggered: {
                MenuState.close()
                SystemTools.runOrNotify(Settings.bluetoothSettingsCommand, "Bluetooth manager failed")
            }
        }

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
            objectName: "bluetooth-devices"
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            interactive: contentHeight > height
            spacing: 0
            // every visible value comes from the device or service; the delegate owns no row state, so off-screen instances are safe to recycle
            reuseItems: true
            model: root.open ? Bluetooth.devices : []

            delegate: InlineOptionRow {
                id: _row
                required property var modelData
                required property int index
                width: _list.width
                bottomRadius: _row.index === _list.count - 1 ? root.lastRowRadius : 0

                readonly property bool   _armed: root._confirm.key === "disconnect:" + modelData.address && modelData.connected
                readonly property bool   _forgetArmed: root._confirm.key === "forget:" + modelData.address
                readonly property bool   _failed: Bluetooth.errorAddr === modelData.address
                readonly property int _batt: Bluetooth.batteryPercent(modelData)
                readonly property bool _busy: Bluetooth.deviceBusy(modelData.state, modelData.pairing, _row._failed)
                readonly property string _state:
                    _forgetArmed ? "Forget?"
                    : _armed ? "Disconnect?"
                    : modelData.pairing ? "Cancel?"
                    : _row._busy && modelData.state === Bt.BluetoothDeviceState.Connecting ? "Connecting…"
                    : _row._busy ? "Disconnecting…"
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
                busy: _row._busy
                interactive: !_row._busy

                function _activate(): void {
                    const addr = modelData.address
                    if (_row._forgetArmed) root._confirm.clear()
                    if (modelData.pairing) {
                        Bluetooth.cancelPair(addr)
                    } else if (modelData.connected) {
                        if (root._confirm.press("disconnect:" + addr)) Bluetooth.disconnectDevice(addr)
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
                    if (root._confirm.press("forget:" + modelData.address)) Bluetooth.forgetDevice(modelData.address)
                }
                TapHandler {
                    enabled: _row.interactive
                    acceptedButtons: Qt.RightButton | Qt.MiddleButton
                    onTapped: _row._forgetTap()
                }
                // the keyboard's right-click, as Delete removes a message in history
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Delete || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
                    event.accepted = true
                    if (_row.interactive && !event.isAutoRepeat) _row._forgetTap()
                }
            }
        }

        HintText {
            visible: root.open && Bluetooth.errorAddr.length > 0
            // the reason never reaches QML: a device that is off or out of range fails the same way
            // as one that lost its pairing key, and only the second is fixed by pairing again
            text: Bluetooth.errorKind === "pair"
                ? "Needs a passkey? Start a pairing agent such as blueman-applet, then retry."
                : "Check it is on and nearby, or right-click it or press Delete twice to forget and pair again."
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
