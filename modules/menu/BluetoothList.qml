pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth as Bt
import "../../config"
import "../../services"
import "../common"

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
        running: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length === 0
        onRunningChanged: if (running) root._searchLapsed = false
        onTriggered: root._searchLapsed = true
    }

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
    Component.onCompleted: _syncScanState()
    Component.onDestruction: Bluetooth.setScan(false)

    Connections {
        target: Bluetooth
        function onAvailableChanged() { root._syncScanState() }
        function onEnabledChanged() { root._syncScanState() }
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
        spacing: 4
        topPadding: 4
        bottomPadding: 4

        Text {
            visible: root.open && (!Bluetooth.available || !Bluetooth.enabled || Bluetooth.devices.length === 0)
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: !Bluetooth.available ? "Bluetooth unavailable"
                : !Bluetooth.enabled   ? "Bluetooth is off"
                : root._searchLapsed   ? "No devices found"
                :                        "Searching for devices…"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
        }

        ListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            clip: true
            interactive: contentHeight > height
            boundsMovement: Flickable.StopAtBounds
            flickDeceleration: 1800
            maximumFlickVelocity: 2200
            spacing: 4
            model: root.open ? Bluetooth.devices : []

            function _focusIndex(index: int): void {
                if (count <= 0) return
                const i = Math.max(0, Math.min(count - 1, index))
                currentIndex = i
                positionViewAtIndex(i, ListView.Contain)
                Qt.callLater(function() {
                    const item = _list.itemAtIndex(i)
                    if (item) item.forceActiveFocus()
                })
            }

            delegate: Rectangle {
                id: _row
                required property var modelData
                required property int index
                width: _list.width
                height: 40
                radius: 10
                antialiasing: true
                color: Theme.rowFill(_ma.containsMouse, false)
                border.width: activeFocus ? 2 : 1
                border.color: (_armed || modelData.pairing) ? Theme.withAlpha(Theme.warning, 0.55)
                            : modelData.connected               ? Theme.withAlpha(Theme.accent,  0.45)
                            : activeFocus                        ? Theme.withAlpha(Theme.accent,  0.45)
                            :                                     Theme.menuCardBorder
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                activeFocusOnTab: true
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.deviceName || modelData.name || modelData.address || "Unknown device"
                Accessible.description: _state

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
                Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }
                Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }
                Keys.onUpPressed:     event => { _list._focusIndex(_row.index - 1); event.accepted = true }
                Keys.onDownPressed:   event => { _list._focusIndex(_row.index + 1); event.accepted = true }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        _list._focusIndex(0)
                        event.accepted = true
                    } else if (event.key === Qt.Key_End) {
                        _list._focusIndex(_list.count - 1)
                        event.accepted = true
                    }
                }

                MouseArea {
                    id: _ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: _row._activate()
                }

                Text {
                    id: _g
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._devGlyph(_row.modelData.icon)
                    color: _row.modelData.connected ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.8)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.left: _g.right; anchors.leftMargin: 10
                    anchors.right: _stateText.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: _row.modelData.deviceName || _row.modelData.name || _row.modelData.address || "Unknown"
                    textFormat: Text.PlainText
                    color: _row.modelData.connected ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    font.weight: _row.modelData.connected ? Font.Medium : Font.Normal
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
                Text {
                    id: _stateText
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent._state
                    color: (parent._armed || _row.modelData.pairing) ? Theme.warning
                         : _row.modelData.connected ? Theme.accent
                         : Theme.withAlpha(Theme.subtext, 0.55)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                    font.weight: (parent._armed || _row.modelData.pairing) ? Font.Medium : Font.Normal
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }
    }

    ListEdgeFade {
        x: 0; y: _col.y + _list.y
        width: parent.width; height: _list.height
        visible: _list.visible
        list: _list
    }
}
