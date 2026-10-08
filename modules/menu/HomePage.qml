pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "controls"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight
    onPageHidden: {
        _picker = ""
        _volumeRow.open = false
        _brightnessRow.open = false
    }

    property string _picker: ""
    readonly property bool _avShown: Audio.ready || _brightnessAvailable
    readonly property bool _connShown: _wifiAvailable || _btAvailable || _signInShown
    function _bottom(item, shown: bool): real {
        return item.y + (shown ? item.height : 0)
    }
    // icon inset + glyph slot + gap, where every Home row's text and slider begin
    readonly property int _rowTextX: 42
    readonly property bool _wifiAvailable: Network.toolAvailable && Network.hasWifiDevice
    readonly property bool _btAvailable: Bluetooth.available
    readonly property bool _signInShown: Network.signInNeeded && Network.canOpenSignIn
    readonly property bool _brightnessAvailable: Brightness.controllable
    readonly property bool _wifiPickerOpen: _picker === "wifi"
    readonly property bool _btPickerOpen: _picker === "bt"

    function _togglePicker(which: string): void {
        if (_picker === which) {
            root._closePicker()
            return
        }
        root._closePicker()
        _volumeRow.closeInline()
        _brightnessRow.closeInline()
        _picker = which
    }

    function _closePicker(): bool {
        if (root._picker === "") return false
        root._picker = ""
        return true
    }

    function dismissInline(): bool {
        if (_volumeRow.open) {
            _volumeRow.closeInline()
            return true
        }
        if (_brightnessRow.open) {
            _brightnessRow.closeInline()
            return true
        }
        return root._closePicker()
    }

    Connections {
        target: Network
        enabled: root.active
        function onWifiEnabledChanged() {
            if (root._picker === "wifi" && !Network.wifiEnabled) root._closePicker()
        }
        function onToolAvailableChanged() {
            if (root._picker === "wifi" && !Network.toolAvailable) root._closePicker()
        }
    }
    Connections {
        target: Bluetooth
        enabled: root.active
        function onEnabledChanged() {
            if (root._picker === "bt" && !Bluetooth.enabled) root._closePicker()
        }
        function onAvailableChanged() {
            if (root._picker === "bt" && !Bluetooth.available) root._closePicker()
        }
    }
    Connections {
        target: NightLight
        enabled: root.active
        function onEnabledChanged() {
            if (root._picker === "nightlight" && !NightLight.enabled) root._closePicker()
        }
        function onToolAvailableChanged() {
            if (root._picker === "nightlight" && !NightLight.toolAvailable) root._closePicker()
        }
    }
    Connections {
        target: PowerProfiles
        enabled: root.active
        function onAvailableChanged() {
            if (root._picker === "power" && !PowerProfiles.available) root._closePicker()
        }
    }

    Item {
        id: _col
        width: parent.width
        implicitHeight: _systemGroup.y + _systemGroup.height + 8

        // inset like the section labels, so all text outside the cards shares one edge
        HomeHeader {
            id: _header
            x: 4
            width: parent.width - 8
        }

        Column {
            id: _avGroup
            y: _header.height
            width: parent.width
            visible: root._avShown

            SectionLabel {
                label: Audio.ready && root._brightnessAvailable ? "Audio & Display"
                     : root._brightnessAvailable ? "Display"
                     : "Audio"
            }
            SettingsCard {
                dividerIndent: root._rowTextX

                VolumeRow {
                    id: _volumeRow
                    visible: Audio.ready
                    reserveExpandSlot: _brightnessRow.visible && Brightness.devices.length > 1
                    onOpenChanged: if (open) {
                        root._closePicker()
                        _brightnessRow.closeInline()
                    }
                }
                BrightnessRow {
                    id: _brightnessRow
                    visible: root._brightnessAvailable
                    reserveExpandSlot: _volumeRow.visible && Audio.sinkCount > 1
                    onOpenChanged: if (open) {
                        root._closePicker()
                        _volumeRow.closeInline()
                    }
                }
                HintText {
                    visible: root._brightnessAvailable && Brightness.lastError.length > 0
                    text: Brightness.lastError
                    textColor: Theme.withAlpha(Theme.error, 0.90)
                }
            }
        }

        Column {
            id: _connGroup
            y: root._bottom(_avGroup, root._avShown)
            width: parent.width
            visible: root._connShown

            SectionLabel { label: "Connectivity" }
            SettingsCard {
                dividerIndent: root._rowTextX

                ControlRow {
                    id: _wifiRow
                    visible: root._wifiAvailable
                    readonly property bool _ethActive: Network.connected && Network.deviceType === "ethernet"
                    active: Network.wifiEnabled
                    glyph: Network.wifiEnabled
                        ? (!Network.isWifi || !Network.connected ? "󰤨"
                            : Network.connectivityIssue.length > 0 ? Network.issueGlyph(true, Network.signalStrength)
                            : Network.signalGlyph(Network.signalStrength))
                        : "󰤭"
                    title: "Wi-Fi"
                    status: Network.wifiHardBlocked ? "Blocked by the hardware switch"
                          : Network.wifiConnecting.length > 0 ? "Connecting to " + SafeText.singleLineText(Network.wifiConnecting, 128)
                          : Network.wifiError.length > 0 ? "Couldn't connect to " + SafeText.singleLineText(Network.wifiError, 128)
                          : Network.wifiEnabled && Network.isWifi && Network.connected ? _withIssue(Network.connectionName)
                          : _ethActive ? _withIssue("Ethernet active")
                          : Network.wifiEnabled ? "Not connected"
                          : "Off"
                    statusColor: Network.wifiHardBlocked ? Theme.warning
                        : Network.wifiConnecting.length > 0 ? Theme.accent
                        : Network.wifiError.length > 0 ? Theme.error
                        : Network.connectivityText.length > 0 ? Theme.warning
                        : "transparent"
                    function _withIssue(link: string): string {
                        return Network.connectivityText.length > 0 ? link + " · " + Network.connectivityText : link
                    }
                    showSwitch: true
                    available: !Network.wifiHardBlocked
                    expandable: Network.wifiEnabled
                    expanded: root._wifiPickerOpen
                    onActivated: Network.toggleWifi()
                    onExpandToggled: root._togglePicker("wifi")
                }

                InlinePicker {
                    id: _wifiPicker
                    open: root._wifiPickerOpen
                    content: Component {
                        WifiList {
                            width: parent.width
                            open: root._wifiPickerOpen
                        }
                    }
                }

                ControlRow {
                    id: _signInRow
                    visible: root._signInShown
                    glyph: "󰖟"
                    title: "Sign in to this network"
                    status: "Opens its login page in your browser"
                    onActivated: {
                        MenuState.close()
                        Network.openSignIn()
                    }
                }

                ControlRow {
                    id: _btRow
                    visible: root._btAvailable
                    active: Bluetooth.enabled
                    glyph: !Bluetooth.enabled ? "󰂲"
                        : Bluetooth.connectedCount === 1 && Bluetooth.connectedGlyph.length > 0
                            ? Bluetooth.connectedGlyph : "󰂯"
                    title: "Bluetooth"
                    status: Bluetooth.hardBlocked ? "Blocked by the hardware switch"
                        : Bluetooth.statusText
                    statusColor: Bluetooth.hardBlocked ? Theme.warning : "transparent"
                    showSwitch: true
                    available: !Bluetooth.hardBlocked
                    expandable: Bluetooth.enabled
                    expanded: root._btPickerOpen
                    onActivated: Bluetooth.toggle()
                    onExpandToggled: root._togglePicker("bt")
                }

                InlinePicker {
                    id: _btPicker
                    open: root._btPickerOpen
                    content: Component {
                        BluetoothList {
                            width: parent.width
                            open: root._btPickerOpen
                            // last thing in the Connectivity card, so its last row owns the corner
                            lastRowRadius: Theme.radiusCard
                        }
                    }
                }
            }
        }

        Column {
            id: _controlsGroup
            y: root._bottom(_connGroup, root._connShown)
            width: parent.width

            SectionLabel { label: "Controls" }
            SettingsCard {
                dividerIndent: root._rowTextX

                ControlRow {
                    id: _nightRow
                    visible: NightLight.toolAvailable
                    active: NightLight.enabled
                    glyph: NightLight.enabled ? "󰖔" : "󰖙"
                    title: "Night Light"
                    status: NightLight.lastError.length > 0 ? NightLight.lastError
                          : NightLight.enabled ? (ShellSettings.nightLightAuto ? "Auto · " : "")
                              + NightLight.temperature + "K" : NightLight.offStatus
                    accentColor: NightLight.lastError.length > 0 ? Theme.error : Theme.warning
                    statusColor: NightLight.lastError.length > 0 ? Theme.error : "transparent"
                    showSwitch: true
                    expandable: NightLight.enabled
                    expanded: root._picker === "nightlight"
                    onActivated: NightLight.toggle()
                    onExpandToggled: root._togglePicker("nightlight")
                }

                InlinePicker {
                    id: _nightPicker
                    open: root._picker === "nightlight"
                    content: Component {
                        Column {
                            width: parent ? parent.width : 0
                            spacing: 0

                            ToggleRow {
                                glyph: "󰖙"
                                label: "Follow sun position"
                                checked: ShellSettings.nightLightAuto
                                onToggled: nextChecked => ShellSettings.nightLightAuto = nextChecked
                            }
                            CollapsibleSection {
                                expanded: !ShellSettings.nightLightAuto
                                SliderRow {
                                    id: _nightTemp
                                    glyph: "󰔄"
                                    label: "Temperature"
                                    displayValue: Math.round(_nightTemp.shownValue) + "K"
                                    value: ShellSettings.nightLightTemp
                                    min: 1000; max: 6500; step: 100
                                    // each value relaunches the gamma tool, which drops to white in between
                                    commitOnRelease: true
                                    glyphColor: Theme.withAlpha(Theme.warning, 0.85)
                                    onChanged: (v) => ShellSettings.nightLightTemp = v
                                }
                            }
                            CollapsibleSection {
                                expanded: ShellSettings.nightLightAuto
                                HintText { text: "Temperature tracks sunset and sunrise at " + NightLight.locationLabel + "." }
                            }
                            SunArc {
                                shown: root._picker === "nightlight" && MenuState.open
                            }
                        }
                    }
                }

                ControlRow {
                    id: _dndRow
                    active: Notifications.dnd
                    glyph: Notifications.silencingActive ? "󰂛" : "󰂚"
                    title: "Do Not Disturb"
                    status: Notifications.effectiveDnd && !Notifications.dnd ? "Quiet hours"
                        : Notifications.fullscreenSilenced ? "Fullscreen"
                        : ""
                    showSwitch: true
                    badgeCount: Notifications.silencingActive ? Notifications.missedCount : 0
                    onActivated: Notifications.toggleDnd()
                    onBadgeActivated: MenuState.showTab(MenuState.recentTab)
                }

                ControlRow {
                    id: _awakeRow
                    active: Idle.keepAwake
                    glyph: Idle.keepAwake ? "󰅶" : "󰛊"
                    title: "Keep Awake"
                    showSwitch: true
                    onActivated: Idle.toggleKeepAwake()
                }


                ControlRow {
                    id: _powerRow
                    visible: PowerProfiles.available
                    available: PowerProfiles.profile !== "" && !PowerProfiles.changing
                    active: PowerProfiles.profile !== "" && PowerProfiles.profile !== "balanced"
                    glyph: PowerProfiles.glyph
                    title: "Power Mode"
                    valueText: PowerProfiles.changing ? "Changing…"
                             : PowerProfiles.profile !== "" ? PowerProfiles.label
                             : "Unavailable"
                    status: PowerProfiles.lastError.length > 0 ? PowerProfiles.lastError
                          : PowerProfiles.degraded ? "Throttled" : ""
                    accentColor: PowerProfiles.lastError.length > 0 || PowerProfiles.degraded
                        ? Theme.error : Theme.accent
                    statusColor: PowerProfiles.lastError.length > 0 ? Theme.error
                        : PowerProfiles.degraded ? Theme.warning : "transparent"
                    expandable: PowerProfiles.choices.length > 1
                    expanded: root._picker === "power"
                    onActivated: root._togglePicker("power")
                    onExpandToggled: root._togglePicker("power")
                }

                InlinePicker {
                    id: _powerPicker
                    open: root._picker === "power"
                    content: Component {
                        Column {
                            width: parent ? parent.width : 0
                            spacing: 0

                            Repeater {
                                model: PowerProfiles.choices

                                InlineOptionRow {
                                    required property var modelData
                                    glyph: modelData.glyph
                                    label: modelData.label
                                    accessiblePrefix: "Power Mode"
                                    selected: PowerProfiles.profile === modelData.name
                                    interactive: !PowerProfiles.changing
                                    onTriggered: PowerProfiles.setProfile(modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            id: _systemGroup
            y: _controlsGroup.y + _controlsGroup.height
            width: parent.width

            SectionLabel { label: "System" }
            VitalsStrip {
                active: root.active
                dividerIndent: root._rowTextX
                width: parent.width
            }
        }
    }
}
