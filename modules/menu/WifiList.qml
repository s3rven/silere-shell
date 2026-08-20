pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _selected: ""
    property string _armedSsid: ""
    property real _armedAtMs: 0
    Timer { id: _disarmTimer; interval: 3000; onTriggered: root._armedSsid = "" }

    function _canScan(): bool {
        return root.open && Network.toolAvailable && Network.wifiEnabled && !Idle.isIdle
    }

    function _syncScanState(): void {
        if (_canScan()) {
            Network.scanWifi(true)
        } else if (root.open) {
            _selected = ""
            _disarmTimer.stop()
            _armedSsid = ""
            Network.clearWifiScan()
        }
    }

    onOpenChanged: {
        if (open) _syncScanState()
        else      { _selected = ""; _disarmTimer.stop(); _armedSsid = ""; Network.clearWifiScan() }
    }
    Component.onCompleted: _syncScanState()
    Component.onDestruction: {
        if (open) Network.clearWifiScan()
    }

    Timer {
        id: _rescan
        interval: 8000
        repeat: true
        // paused while a password row is open so a scan can't rebuild the field mid-typing
        running: root._canScan() && root._selected === "" && !Idle.isIdle
        onTriggered: Network.scanWifi(false)
    }

    Connections {
        target: Network
        function onWifiConnectingChanged() {
            if (Network.wifiConnecting === "" && Network.wifiError === "") root._selected = ""
        }
        function onWifiEnabledChanged() { root._syncScanState() }
        function onToolAvailableChanged() { root._syncScanState() }
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
            visible: root.open && Network.wifiNetworks.length === 0
            width: parent.width
            height: Metrics.rowHeightFor(32)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: !Network.toolAvailable ? "Wi-Fi unavailable"
                : Network.wifiHardBlocked ? "Blocked by the hardware switch"
                : !Network.wifiEnabled   ? "Wi-Fi is off"
                : Network.wifiScanning   ? "Searching for networks…"
                :                          "No networks found"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.pixelSize: Settings.fontLabel
        }

        ShellListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Network.wifiNetworks.length > 0
            interactive: contentHeight > height
            spacing: 0
            model: root.open ? Network.wifiNetworks : []

            delegate: Column {
                id: _entry
                required property var modelData
                required property int index
                width: _list.width
                spacing: 0

                readonly property bool _armed:      root._armedSsid === modelData.ssid && modelData.active
                readonly property bool _sel:        root._selected === modelData.ssid
                readonly property bool _connecting: Network.wifiConnecting === modelData.ssid
                readonly property bool _failed:     Network.wifiError === modelData.ssid

                function _submitPassword(): void {
                    const secret = _pw.text
                    _pw.text = ""
                    if (secret.length > 0) Network.connectWifi(modelData.ssid, secret)
                }

                on_SelChanged: if (!_sel) _pw.text = ""

                InlineOptionRow {
                    id: _row
                    width: parent.width
                    glyph: Network.signalGlyph(_entry.modelData.signal)
                    label: _entry.modelData.label
                    status: _entry._armed ? "Disconnect?"
                        : _entry.modelData.active ? "Connected"
                        : _entry._connecting ? "Connecting…"
                        : _entry._failed ? (Network.wifiErrorNeedsSecret ? "Wrong password" : "Failed")
                        : _entry._sel ? "Password"
                        : _entry.modelData.secured ? "Secured"
                        : "Open"
                    selected: _entry.modelData.active
                    highlighted: _entry._sel
                    warning: _entry._armed
                    failed:  _entry._failed

                    function _activate(): void {
                        if (_entry.modelData.active) {
                            if (_entry._armed) {
                                // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
                                if (Date.now() - root._armedAtMs < Metrics.confirmGuardMs) return
                                root._armedSsid = ""
                                _disarmTimer.stop()
                                Network.disconnectWifi()
                            } else {
                                root._armedSsid = _entry.modelData.ssid
                                root._armedAtMs = Date.now()
                                _disarmTimer.restart()
                            }
                            return
                        }
                        // a known network reconnects from its stored key; once that key is
                        // refused, repeating it can only fail again, so take a new one
                        const needsSecret = !_entry.modelData.known
                            || (_entry._failed && Network.wifiErrorNeedsSecret)
                        if (_entry.modelData.secured && needsSecret) {
                            const wasSel = _entry._sel
                            root._selected = wasSel ? "" : _entry.modelData.ssid
                            Network.clearWifiError()
                            if (!wasSel) Qt.callLater(function() { _pw.forceActiveFocus() })
                        } else {
                            Network.connectWifi(_entry.modelData.ssid, "")
                        }
                    }
                    onTriggered: _activate()
                }

                Item {
                    width: parent.width
                    height: _entry._sel ? 40 : 0
                    clip: true
                    visible: height > 0.5
                    Disclosure on height { expanded: _entry._sel }

                    Rectangle {
                        id: _pwField
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(0, parent.width - 16)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        height: Metrics.rowHeightFor(36)
                        radius: Theme.radiusField
                        antialiasing: true
                        color: Theme.menuControl

                        OutlineBorder {
                            radius: _pwField.radius
                            outlineColor: _entry._failed ? Theme.withAlpha(Theme.error, 0.5)
                                                         : _pw.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                                                                            : Theme.menuControlLine
                            ColorFade on outlineColor {}
                        }

                        Connections {
                            target: Network
                            function onWifiErrorChanged() {
                                if (_entry._failed) _pw.text = ""
                            }
                        }

                        TextInput {
                            id: _pw
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.right: _join.left; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            // echoMode alone leaves inputMethodHints at 0: an IME still
                            // capitalises the first letter of a case-sensitive WPA key
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                                | Qt.ImhNoAutoUppercase
                            color: Theme.text
                            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize
                            clip: true
                            onAccepted: _entry._submitPassword()
                            Keys.onEscapePressed: event => { root._selected = ""; event.accepted = true }

                            ShellText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: _pw.text.length === 0
                                text: !_entry._failed ? "Password"
                                    : Network.wifiErrorNeedsSecret ? "Wrong password" : "Connection failed"
                                color: _entry._failed ? Theme.withAlpha(Theme.error, 0.7)
                                                      : Theme.withAlpha(Theme.subtext, 0.45)
                                font.pixelSize: Settings.fontSize
                            }
                        }

                        Rectangle {
                            id: _join
                            anchors.right: parent.right; anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 28; radius: Theme.radiusField
                            antialiasing: true
                            enabled: _pw.text.length > 0 && !_entry._connecting
                            opacity: enabled ? 1.0 : Theme.disabledOpacity
                            MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                            color: (_joinHover.hovered) ? Theme.withAlpha(Theme.accent, 0.30)
                                                                        : Theme.withAlpha(Theme.accent, 0.18)
                            ColorFade on color {}

                            function _activate(): void {
                                if (_join.enabled) _entry._submitPassword()
                            }

                            HoverHandler { id: _joinHover; enabled: _join.enabled; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { enabled: _join.enabled; onTapped: _join._activate() }
                            ShellText {
                                anchors.centerIn: parent
                                text: "󰌑"
                                color: Theme.accent
                                font.pixelSize: Settings.fontSize + 1
                            }
                        }
                    }
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
