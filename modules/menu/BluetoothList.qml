import QtQuick
import Quickshell.Bluetooth as Bt
import "../../config"
import "../../services"
import "../common"

// Inline Bluetooth device picker. Discovery runs only while `open`, so it costs
// nothing when collapsed. Device actions go straight to the native objects.
Item {
    id: root

    property bool open: false

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _armedAddr: ""
    Timer { id: _disarmTimer; interval: 3000; onTriggered: root._armedAddr = "" }

    function _syncScanState(): void {
        Bluetooth.setScan(root.open && Bluetooth.available && Bluetooth.enabled)
        if (!Bluetooth.available || !Bluetooth.enabled) {
            _disarmTimer.stop()
            root._armedAddr = ""
        }
    }

    onOpenChanged: {
        _syncScanState()
        if (!open) { _disarmTimer.stop(); root._armedAddr = "" }
    }
    Component.onDestruction: Bluetooth.setScan(false)

    Connections {
        target: Bluetooth
        function onAvailableChanged() { root._syncScanState() }
        function onEnabledChanged() { root._syncScanState() }
    }

    function _devGlyph(icon) {
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
        spacing: 4
        topPadding: 4
        bottomPadding: 4

        Text {
            visible: !Bluetooth.available || !Bluetooth.enabled || Bluetooth.devices.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            // Match reality instead of implying a scan that can't run when the
            // adapter is off or absent.
            text: !Bluetooth.available ? "Bluetooth unavailable"
                : !Bluetooth.enabled   ? "Bluetooth is off"
                :                        "Searching for devices…"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
        }

        ListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            clip: true
            boundsMovement: Flickable.StopAtBounds
            spacing: 4
            model: Bluetooth.devices

            delegate: Rectangle {
                required property var modelData
                width: _list.width
                height: 40
                radius: 10
                antialiasing: true
                color: Theme.rowFill(_ma.containsMouse, false)
                border.width: 1
                border.color: (_armed || modelData.pairing) ? Theme.withAlpha(Theme.warning, 0.55)
                            : modelData.connected               ? Theme.withAlpha(Theme.accent,  0.45)
                            :                                     Theme.withAlpha(Theme.subtext, 0.10)
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                readonly property bool   _armed: root._armedAddr === modelData.address && modelData.connected
                readonly property int _batt: Math.round(modelData.battery > 1 ? modelData.battery : modelData.battery * 100)
                readonly property string _state:
                    _armed ? "Disconnect?"
                    : modelData.pairing ? "Cancel?"
                    : modelData.state === Bt.BluetoothDeviceState.Connecting    ? "Connecting…"
                    : modelData.state === Bt.BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : modelData.connected ? (modelData.batteryAvailable ? _batt + "%" : "Connected")
                    : modelData.paired    ? "Paired"
                    : "Pair"

                MouseArea {
                    id: _ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
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
                }

                Text {
                    id: _g
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._devGlyph(modelData.icon)
                    color: modelData.connected ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.8)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.left: _g.right; anchors.leftMargin: 10
                    anchors.right: _stateText.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.deviceName || modelData.name || modelData.address || "Unknown"
                    textFormat: Text.PlainText
                    color: modelData.connected ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    font.weight: modelData.connected ? Font.Medium : Font.Normal
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
                Text {
                    id: _stateText
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent._state
                    color: (parent._armed || modelData.pairing) ? Theme.warning
                         : modelData.connected ? Theme.accent
                         : Theme.withAlpha(Theme.subtext, 0.55)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                    font.weight: (parent._armed || modelData.pairing) ? Font.Medium : Font.Normal
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }
    }

    // Overflow cue: fades appear once the list scrolls.
    ListEdgeFade {
        x: 0; y: _col.y + _list.y
        width: parent.width; height: _list.height
        visible: _list.visible
        list: _list
    }
}
