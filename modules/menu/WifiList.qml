pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

// Inline Wi-Fi picker. Rescans only while `open`. Tapping an open or already
// saved network connects straight away; a new secured network reveals an inline
// password field. Connect/scan logic lives in the Network service.
Item {
    id: root

    property bool open: false

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _selected: ""   // ssid awaiting password entry

    function _canScan(): bool {
        return root.open && Network.toolAvailable && Network.wifiEnabled
    }

    function _syncScanState(): void {
        if (_canScan()) {
            Network.scanWifi(true)
        } else if (root.open) {
            _selected = ""
            Network.clearWifiScan()
        }
    }

    onOpenChanged: {
        if (open) _syncScanState()
        else      { _selected = ""; Network.clearWifiScan() }
    }

    Timer {
        id: _rescan
        interval: 8000
        repeat: true
        // paused while a password row is open so a scan can't rebuild the field mid-typing
        running: root._canScan() && root._selected === ""
        onTriggered: Network.scanWifi(false)
    }

    // Close the password row once a connect succeeds (failure keeps it open).
    Connections {
        target: Network
        function onWifiConnectingChanged() {
            if (Network.wifiConnecting === "" && Network.wifiError === "") root._selected = ""
        }
        function onWifiEnabledChanged() { root._syncScanState() }
        function onToolAvailableChanged() { root._syncScanState() }
    }

    function _sigGlyph(s) {
        if (s > 75) return "󰤨"
        if (s > 50) return "󰤥"
        if (s > 25) return "󰤢"
        return "󰤟"
    }

    Column {
        id: _col
        width: parent.width
        spacing: 4
        topPadding: 4
        bottomPadding: 4

        Text {
            visible: root.open && Network.wifiNetworks.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            // Don't claim to be scanning when the radio is off — it never will.
            text: !Network.toolAvailable ? "Wi-Fi unavailable"
                : !Network.wifiEnabled   ? "Wi-Fi is off"
                : Network.wifiScanFailed ? "Could not scan for networks"
                : Network.wifiScanning   ? "Searching for networks…"
                :                          "No networks found"
            color: Network.wifiScanFailed ? Theme.withAlpha(Theme.error, 0.75)
                                           : Theme.withAlpha(Theme.subtext, 0.5)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
        }

        ListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Network.wifiNetworks.length > 0
            clip: true
            boundsMovement: Flickable.StopAtBounds
            spacing: 4
            model: root.open ? Network.wifiNetworks : []

            delegate: Column {
                id: _entry
                required property var modelData
                width: _list.width
                spacing: 0

                readonly property bool _sel:        root._selected === modelData.ssid
                readonly property bool _connecting: Network.wifiConnecting === modelData.ssid
                readonly property bool _failed:     Network.wifiError === modelData.ssid

                Rectangle {
                    width: parent.width
                    height: 40
                    radius: 10
                    antialiasing: true
                    color: Theme.rowFill(_rowHover.hovered, false)
                    border.width: activeFocus ? 2 : 1
                    border.color: activeFocus ? Theme.withAlpha(Theme.accent, 0.55)
                                : modelData.active ? Theme.withAlpha(Theme.accent, 0.45)
                                                   : Theme.withAlpha(Theme.subtext, 0.10)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    activeFocusOnTab: true
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.ssid
                    Accessible.description: modelData.active ? "Connected"
                        : _entry._connecting ? "Connecting"
                        : modelData.secured ? "Secured network"
                        : "Open network"

                    function _activate(): void {
                        if (modelData.active) { Network.disconnectWifi(); return }
                        if (modelData.secured && !modelData.known) {
                            const wasSel = _entry._sel
                            root._selected = wasSel ? "" : modelData.ssid
                            Network.clearWifiError()
                            if (!wasSel) Qt.callLater(function() { _pw.forceActiveFocus() })
                        } else {
                            Network.connectWifi(modelData.ssid, "")
                        }
                    }
                    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }
                    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _activate(); event.accepted = true }

                    HoverHandler { id: _rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: _activate() }

                    Text {
                        id: _sig
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._sigGlyph(modelData.signal)
                        color: modelData.active ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.8)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                        renderType: Text.NativeRendering
                    }
                    Text {
                        anchors.left: _sig.right; anchors.leftMargin: 10
                        anchors.right: _icons.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.ssid
                        textFormat: Text.PlainText
                        color: modelData.active ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize
                        font.weight: modelData.active ? Font.Medium : Font.Normal
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                    Row {
                        id: _icons
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            visible: _entry._connecting
                            text: "Connecting…"
                            color: Theme.withAlpha(Theme.subtext, 0.7)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                        Text {
                            visible: modelData.active && !_entry._connecting
                            text: "󰄬"
                            color: Theme.accent
                            font.family: Settings.font; font.pixelSize: Settings.fontSize
                            renderType: Text.NativeRendering
                        }
                        Text {
                            visible: modelData.secured && !_entry._connecting
                            text: "󰌾"
                            color: Theme.withAlpha(Theme.subtext, 0.5)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // Inline password entry for a new secured network.
                Item {
                    width: parent.width
                    height: _entry._sel ? 44 : 0
                    clip: true
                    visible: height > 0.5
                    Behavior on height { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: parent.width
                        anchors.bottom: parent.bottom
                        height: 38
                        radius: 10
                        antialiasing: true
                        color: Theme.mix(Theme.surface, Theme.subtext, 0.09)
                        border.width: 1
                        border.color: _entry._failed ? Theme.withAlpha(Theme.error, 0.5)
                                                      : Theme.withAlpha(Theme.accent, 0.3)
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        TextInput {
                            id: _pw
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.right: _join.left; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: Theme.text
                            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize
                            renderType: Text.NativeRendering
                            clip: true
                            onAccepted: if (text.length > 0) Network.connectWifi(_entry.modelData.ssid, text)

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: _pw.text.length === 0
                                text: _entry._failed ? "Connection failed" : "Password"
                                color: _entry._failed ? Theme.withAlpha(Theme.error, 0.7)
                                                      : Theme.withAlpha(Theme.subtext, 0.45)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }
                        }

                        Rectangle {
                            id: _join
                            anchors.right: parent.right; anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 28; radius: 8
                            antialiasing: true
                            enabled: _pw.text.length > 0 && !_entry._connecting
                            opacity: enabled ? 1.0 : 0.4
                            color: _joinHover.hovered ? Theme.withAlpha(Theme.accent, 0.30)
                                                      : Theme.withAlpha(Theme.accent, 0.18)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            HoverHandler { id: _joinHover; enabled: _join.enabled; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { enabled: _join.enabled; onTapped: Network.connectWifi(_entry.modelData.ssid, _pw.text) }
                            Text {
                                anchors.centerIn: parent
                                text: "󰌑"
                                color: Theme.accent
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                            }
                        }
                    }
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
