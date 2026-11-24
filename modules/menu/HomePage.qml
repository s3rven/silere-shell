pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "controls"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight
    onPageShown: {
        if (Network.hasVpn) Network.refreshVpnAddress()
        Vpn.peek()
        root._takePicker()
    }
    onPageHidden: {
        _vpnRow.copied = false
        _picker = ""
        _volumeRow.open = false
        _brightnessRow.open = false
    }

    property string _picker: ""
    signal controlRequested(Item control, Item choices)
    // a light or display that stopped answering keeps its place, or its error has nowhere to show; one switched off has no row
    readonly property bool _displayShown: _brightnessAvailable || KeyboardBrightness.ready
        || KeyboardBrightness.lastError.length > 0
        || DisplayBrightness.controllableDisplays.length > 0
        || (ShellSettings.ddcBrightnessEnabled && DisplayBrightness.lastError.length > 0)
    readonly property bool _avShown: Audio.ready || root._displayShown
    // nothing to pick without a saved profile, so the row waits for one; a failed read leaves none, and the picker shows that error
    readonly property bool _vpnShown: Network.hasVpn
        || (Vpn.available && (Vpn.profiles.length > 0 || Vpn.lastError.length > 0))
    readonly property bool _connShown: _wiredShown || _wifiAvailable || _btAvailable || _signInShown || _vpnShown
    function _bottom(item, shown: bool): real {
        return item.y + (shown ? item.height : 0)
    }
    // icon inset + glyph slot + gap, where every Home row's text and slider begin
    readonly property int _rowTextX: 14 + Metrics.glyphSlotWidth + 10
    property bool _wifiAvailable: Network.toolAvailable && Network.hasWifiDevice
    property bool _btAvailable: Bluetooth.available
    property bool _wiredShown: Network.deviceType === "ethernet"
    readonly property bool _signInShown: Network.signInNeeded && Network.canOpenSignIn
    readonly property bool _brightnessAvailable: Brightness.controllable
    readonly property bool _wifiPickerOpen: _picker === "wifi"
    readonly property bool _btPickerOpen: _picker === "bt"

    // switching lists, the old one folds on the new one's curve and only once the new one is laid out: a faster fold, or
    // one that started before the new list's first layout, a frame after its build, shrank the card up to 140 px before it grew
    property string _pickerLeaving: ""
    property InlinePicker _pickerArriving: null
    Connections {
        target: root._pickerArriving
        function onFoldTargetChanged() { root._releaseLeaving() }
    }
    Timer { id: _leavingFallback; interval: 100; onTriggered: root._releaseLeaving() }
    function _releaseLeaving(): void {
        _leavingFallback.stop()
        root._pickerArriving = null
        root._pickerLeaving = ""
    }
    property bool _swapFold: false
    function _listOpen(which: string): bool { return root._picker === which || root._pickerLeaving === which }
    function _armSwapFold(): void {
        if (root._picker === "" && !_volumeRow.open && !_brightnessRow.open) return
        root._swapFold = true
        _swapFoldEnd.restart()
    }
    Timer { id: _swapFoldEnd; interval: Motion.medium + 60; onTriggered: root._swapFold = false }

    function _togglePicker(which: string): void {
        if (_picker === which) {
            root._closePicker()
            return
        }
        root._armSwapFold()
        root._pickerLeaving = root._picker
        root._closePicker()
        _picker = which
        const arriving = root._pickerParts(which)[1]
        if (root._pickerLeaving === "" || !arriving || arriving.foldTarget > 0) {
            root._releaseLeaving()
        } else {
            root._pickerArriving = arriving
            _leavingFallback.restart()
        }
        _volumeRow.closeInline()
        _brightnessRow.closeInline()
        // opened by hand or by a bar shortcut alike: a list past the edge of a tall Home scrolls in, and no further than it must
        const parts = root._pickerParts(which)
        if (parts[0]) root.controlRequested(parts[0], parts[1])
    }

    // a picker's row and the list drawn for it: above the row when the bar is at the bottom
    function _pickerParts(which: string): var {
        const up = Metrics.barAtBottom
        switch (which) {
        case "wifi":       return [_wifiRow, up ? _wifiAbove : _wifiPicker]
        case "vpn":        return [_vpnRow, up ? _vpnAbove : _vpnPicker]
        case "bt":         return [_btRow, up ? _btAbove : _btPicker]
        case "nightlight": return [_nightRow, up ? _nightAbove : _nightPicker]
        case "dnd":        return [_dndRow, up ? _dndAbove : _dndPicker]
        case "awake":      return [_awakeRow, up ? _awakeAbove : _awakePicker]
        case "power":      return [_powerRow, up ? _powerAbove : _powerPicker]
        case "battery":    return [_vitals, null]
        }
        return [null, null]
    }

    // a bar shortcut reveals its control; device choices open only when available
    function _takePicker(): void {
        const want = MenuState.homePicker
        if (want.length === 0) return
        MenuState.homePicker = ""
        if (want === "wired") {
            if (!root._wiredShown) return
            root.dismissInline()
            root.controlRequested(_wiredRow, null)
            return
        }
        if (want === "brightness") {
            const slider = root._brightnessAvailable ? _brightnessRow : _externalBrightnessRows.itemAt(0)
            if (!slider) return
            root._armSwapFold()
            root._closePicker()
            _volumeRow.closeInline()
            _brightnessRow.open = root._brightnessAvailable && _brightnessRow.expandable
            root.controlRequested(slider, null)
            return
        }
        const radioRow = want === "wifi" && root._wifiAvailable ? _wifiRow
            : want === "bt" && root._btAvailable ? _btRow : null
        const allowed = radioRow ? radioRow.expandable
            : want === "power" && PowerProfiles.available && PowerProfiles.choices.length > 1
        // an already open picker is still brought into view
        if (allowed && root._picker !== want) root._togglePicker(want)
        else if (allowed) {
            const parts = root._pickerParts(want)
            root.controlRequested(parts[0], parts[1])
        }
        else if (radioRow || want === "power") {
            root.dismissInline()
            root.controlRequested(radioRow || _vitals, null)
        }
    }
    Connections {
        target: MenuState
        enabled: root.active
        function onHomePickerChanged() { root._takePicker() }
    }

    function _closePicker(): bool {
        if (root._picker === "") return false
        const parts = root._pickerParts(root._picker)
        if (parts[0] && parts[1]) parts[0].restorePickerFocus(parts[1])
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
    }
    on_WifiAvailableChanged: if (root._picker === "wifi" && !root._wifiAvailable) root._closePicker()
    on_VpnShownChanged: if (root._picker === "vpn" && !root._vpnShown) root._closePicker()
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
                label: Audio.ready && root._displayShown ? "Audio & Display"
                     : root._displayShown ? "Display"
                     : "Audio"
            }
            SettingsCard {
                dividerIndent: root._rowTextX

                VolumeRow {
                    id: _volumeRow
                    visible: Audio.ready
                    reserveExpandSlot: _brightnessRow.visible && _brightnessRow.expandable
                    symmetricFold: root._swapFold
                    onOpenChanged: if (open) {
                        root._armSwapFold()
                        root._closePicker()
                        _brightnessRow.closeInline()
                    }
                }
                BrightnessRow {
                    id: _brightnessRow
                    visible: root._brightnessAvailable
                    reserveExpandSlot: _volumeRow.visible && _volumeRow.expandable
                    symmetricFold: root._swapFold
                    onOpenChanged: if (open) {
                        root._armSwapFold()
                        root._closePicker()
                        _volumeRow.closeInline()
                    }
                }
                HintText {
                    visible: root._brightnessAvailable && Brightness.lastError.length > 0
                    text: Brightness.lastError
                    textColor: Theme.withAlpha(Theme.error, 0.90)
                }
                SliderRow {
                    visible: KeyboardBrightness.ready
                    glyph: "󰌌"
                    label: "Keyboard light"
                    min: 0; max: KeyboardBrightness.maximum; step: 1
                    value: KeyboardBrightness.currentLevel
                    displayValue: value === 0 ? "Off" : Math.round(100 * value / Math.max(1, max)) + "%"
                    interactionKey: KeyboardBrightness.key
                    onChanged: value => KeyboardBrightness.setLevel(value)
                }
                HintText {
                    visible: KeyboardBrightness.lastError.length > 0
                    text: KeyboardBrightness.lastError
                    textColor: Theme.menuTextWarning
                }
                Repeater {
                    id: _externalBrightnessRows
                    // with a backlight they fold under its slider; without the scanned level, so a rescan that only read a
                    // new level does not rebuild a slider in use
                    model: root._brightnessAvailable ? []
                        : DisplayBrightness.controllableDisplays.map(d => ({ key: d.key, label: d.label }))
                    SliderRow {
                        required property var modelData
                        glyph: "󰍹"
                        label: modelData.label + " brightness"
                        min: 1; max: 100; step: 1
                        value: DisplayBrightness.levelFor(modelData.key)
                        displayValue: Math.round(shownValue) + "%"
                        interactionKey: modelData.key
                        commitOnRelease: true
                        onChanged: value => DisplayBrightness.setPercent(modelData.key, value)
                    }
                }
                HintText {
                    visible: ShellSettings.ddcBrightnessEnabled && DisplayBrightness.lastError.length > 0
                    text: DisplayBrightness.lastError
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
                    id: _wiredRow
                    visible: root._wiredShown
                    active: true
                    glyph: Network.connectivityText.length > 0 ? Network.issueGlyph(false, 0) : "󰈀"
                    title: "Ethernet"
                    status: Network.connectivityText || Network.connectionName || "Connected"
                    statusColor: Network.connectivityText.length > 0 ? Theme.warning : "transparent"
                    passive: Settings.networkSettingsCommand.length === 0
                    onActivated: {
                        MenuState.close()
                        SystemAlerts.runOrNotify(Settings.networkSettingsCommand, "Network settings failed")
                    }
                }

                InlinePicker { id: _wifiAbove; mirror: _wifiPicker }
                ControlRow {
                    id: _wifiRow
                    visible: root._wifiAvailable
                    readonly property string _issue: Network.isWifi ? Network.connectivityText : ""
                    active: Network.wifiEnabled
                    glyph: Network.wifiEnabled
                        ? (!Network.wifiConnected ? "󰤨"
                            : _issue.length > 0 ? Network.issueGlyph(true, Network.wifiSignalStrength)
                            : Network.signalGlyph(Network.wifiSignalStrength))
                        : "󰤭"
                    title: "Wi-Fi"
                    status: Network.wifiHardBlocked ? "Blocked by the hardware switch"
                          : Network.wifiConnecting.length > 0 ? "Connecting to " + SafeText.singleLineText(Network.wifiConnecting, 128)
                          : Network.wifiError.length > 0 ? "Could not connect to " + SafeText.singleLineText(Network.wifiError, 128)
                          : Network.wifiEnabled && Network.wifiConnected
                              ? [Network.wifiConnectionName || "Connected", _issue].filter(s => s.length > 0).join(" · ")
                          : Network.wifiEnabled ? "Not connected"
                          : ""
                    statusColor: Network.wifiHardBlocked ? Theme.warning
                        : Network.wifiConnecting.length > 0 ? Theme.accent
                        : Network.wifiError.length > 0 ? Theme.error
                        : _issue.length > 0 ? Theme.warning
                        // the accent is for a live connection: on with nothing joined, the line is a plain detail
                        : Network.wifiEnabled && !Network.wifiConnected ? Theme.menuTextDetail
                        : "transparent"
                    showSwitch: true
                    available: !Network.wifiHardBlocked
                    expandable: Network.wifiEnabled
                    expanded: root._wifiPickerOpen
                    onActivated: Network.toggleWifi()
                    onExpandToggled: root._togglePicker("wifi")
                }

                InlinePicker {
                    id: _wifiPicker
                    open: root._listOpen("wifi")
                    symmetric: root._swapFold
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
                    onActivated: {
                        MenuState.close()
                        Network.openSignIn()
                    }
                }

                InlinePicker { id: _vpnAbove; mirror: _vpnPicker }
                ControlRow {
                    id: _vpnRow
                    visible: root._vpnShown
                    property bool copied: false
                    active: Network.hasVpn
                    glyph: "󰦝"
                    title: "VPN"
                    status: copied ? "Address copied" : Network.vpnName
                    valueText: Network.vpnAddress
                    passive: !expandable && Network.vpnAddress.length === 0
                    expandable: SystemTools.hasNmcli && Network.toolAvailable
                    expanded: root._picker === "vpn"
                    onExpandableChanged: if (!expandable && expanded) root._closePicker()
                    onExpandToggled: root._togglePicker("vpn")
                    onActivated: {
                        if (Network.vpnAddress.length === 0) {
                            root._togglePicker("vpn")
                            return
                        }
                        Quickshell.clipboardText = Network.vpnAddress
                        copied = true
                        _copiedHold.restart()
                    }
                    Timer { id: _copiedHold; interval: 1600; onTriggered: _vpnRow.copied = false }
                }

                InlinePicker {
                    id: _vpnPicker
                    open: root._listOpen("vpn")
                    symmetric: root._swapFold
                    content: Component { VpnList { open: root._picker === "vpn" } }
                }

                InlinePicker { id: _btAbove; mirror: _btPicker }
                ControlRow {
                    id: _btRow
                    visible: root._btAvailable
                    active: Bluetooth.enabled
                    glyph: !Bluetooth.enabled ? "󰂲"
                        : Bluetooth.connectedCount === 1 && Bluetooth.connectedGlyph.length > 0
                            ? Bluetooth.connectedGlyph : "󰂯"
                    title: "Bluetooth"
                    status: Bluetooth.hardBlocked ? "Blocked by the hardware switch"
                        : Bluetooth.enabled ? Bluetooth.statusText : ""
                    statusColor: Bluetooth.hardBlocked ? Theme.warning
                        : Bluetooth.enabled && Bluetooth.connectedCount === 0 ? Theme.menuTextDetail : "transparent"
                    showSwitch: true
                    available: !Bluetooth.hardBlocked
                    expandable: Bluetooth.enabled
                    expanded: root._btPickerOpen
                    onActivated: Bluetooth.toggle()
                    onExpandToggled: root._togglePicker("bt")
                }

                InlinePicker {
                    id: _btPicker
                    open: root._listOpen("bt")
                    symmetric: root._swapFold
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

                InlinePicker { id: _nightAbove; mirror: _nightPicker }
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
                    open: root._listOpen("nightlight")
                    symmetric: root._swapFold
                    content: Component {
                        Column {
                            width: parent ? parent.width : 0
                            spacing: 0

                            ToggleRow {
                                glyph: "󰖙"
                                label: "Follow sun position"
                                description: ShellSettings.nightLightAuto ? NightLight.locationLabel : ""
                                checked: ShellSettings.nightLightAuto
                                onToggled: nextChecked => ShellSettings.nightLightAuto = nextChecked
                            }
                            SliderRow {
                                id: _nightTemp
                                glyph: "󰔄"
                                // following the sun, this is where dusk ends
                                label: ShellSettings.nightLightAuto ? "Night temperature" : "Temperature"
                                displayValue: Math.round(_nightTemp.shownValue) + "K"
                                value: ShellSettings.nightLightTemp
                                min: 1000; max: 6500; step: 100
                                // each value relaunches the gamma tool, which drops to white in between
                                commitOnRelease: true
                                glyphColor: Theme.withAlpha(Theme.warning, 0.85)
                                onChanged: (v) => ShellSettings.nightLightTemp = v
                            }
                            SunArc {
                                // not the picker's own state: the arc stays drawn while its picker folds away
                                shown: MenuState.open
                            }
                        }
                    }
                }

                InlinePicker { id: _dndAbove; mirror: _dndPicker }
                ControlRow {
                    id: _dndRow
                    active: Notifications.dnd
                    glyph: Notifications.silencingActive ? "󰂛" : "󰂚"
                    title: "Do Not Disturb"
                    status: Notifications.dndUntil > 0 ? Notifications.dndUntilText
                        : Notifications.effectiveDnd && !Notifications.dnd ? "Quiet hours"
                        : Notifications.fullscreenSilenced ? "Fullscreen"
                        : Notifications.callSilenced ? "In a call"
                        : Notifications.presentationMode ? "Presentation Mode"
                        : Notifications.screenShareSilenced ? "Sharing screen"
                        : ""
                    showSwitch: true
                    expandable: true
                    expanded: root._picker === "dnd"
                    badgeCount: Notifications.missedShown
                    onActivated: Notifications.toggleDnd()
                    onExpandToggled: root._togglePicker("dnd")
                    onBadgeActivated: MenuState.showTab(MenuState.recentTab)
                }

                InlinePicker {
                    id: _dndPicker
                    open: root._listOpen("dnd")
                    symmetric: root._swapFold
                    content: Component {
                        Column {
                            width: parent ? parent.width : 0
                            spacing: 0

                            InlineOptionRow {
                                glyph: "󰔛"
                                label: "For 1 hour"
                                accessiblePrefix: "Do Not Disturb"
                                onTriggered: {
                                    Notifications.setDnd(true, Notifications.dndEndFor(Date.now(), 60))
                                    root._closePicker()
                                }
                            }
                            InlineOptionRow {
                                glyph: "󰖔"
                                label: "Until " + DateTime.hourText(ShellSettings.dndTo)
                                accessiblePrefix: "Do Not Disturb"
                                onTriggered: {
                                    Notifications.setDnd(true,
                                        Notifications.dndEndAtHour(Date.now(), ShellSettings.dndTo))
                                    root._closePicker()
                                }
                            }
                            ToggleRow {
                                glyph: "󰐨"
                                label: "Presentation Mode"
                                description: "Hides popups, keeps the screen awake"
                                checked: Notifications.presentationMode
                                onToggled: nextChecked => Notifications.presentationMode = nextChecked
                            }
                        }
                    }
                }

                InlinePicker { id: _awakeAbove; mirror: _awakePicker }
                ControlRow {
                    id: _awakeRow
                    active: Idle.keepAwake
                    glyph: Idle.keepAwake || Notifications.presentationMode ? "󰅶" : "󰛊"
                    title: "Keep Awake"
                    status: Idle.keepAwake || !Notifications.presentationMode ? Idle.keepAwakeUntilText
                        : "Presentation Mode"
                    showSwitch: true
                    expandable: true
                    expanded: root._picker === "awake"
                    onActivated: Idle.toggleKeepAwake()
                    onExpandToggled: root._togglePicker("awake")
                }

                InlinePicker {
                    id: _awakePicker
                    open: root._listOpen("awake")
                    symmetric: root._swapFold
                    content: Component {
                        Column {
                            width: parent ? parent.width : 0
                            spacing: 0

                            Repeater {
                                model: [1, 2]

                                InlineOptionRow {
                                    required property int modelData
                                    glyph: "󰔛"
                                    label: "For " + modelData + (modelData === 1 ? " hour" : " hours")
                                    accessiblePrefix: "Keep Awake"
                                    onTriggered: {
                                        Idle.keepAwakeFor(Date.now(), modelData * 60)
                                        root._closePicker()
                                    }
                                }
                            }
                        }
                    }
                }

                InlinePicker { id: _powerAbove; mirror: _powerPicker }
                ControlRow {
                    id: _powerRow
                    visible: PowerProfiles.available
                    available: PowerProfiles.profile !== "" && !PowerProfiles.changing
                    active: PowerProfiles.profile !== "" && PowerProfiles.profile !== "balanced"
                    glyph: PowerProfiles.glyph
                    title: "Power Mode"
                    // the mode reads as a subtitle, as Bluetooth's device does: a value is wider than
                    // a switch and pushed this chevron out of the column the rows above share
                    status: PowerProfiles.lastError.length > 0 ? PowerProfiles.lastError
                          : PowerProfiles.changing ? "Changing…"
                          : PowerProfiles.profile === "" ? "Unavailable"
                          : PowerProfiles.degraded ? PowerProfiles.label + " · Throttled"
                          : PowerProfiles.label
                    reserveSwitchSlot: true
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
                    open: root._listOpen("power")
                    symmetric: root._swapFold
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
                            ToggleRow {
                                visible: Battery.available
                                glyph: "󰚥"
                                label: "Remember per power source"
                                checked: ShellSettings.powerProfileRemember
                                onToggled: nextChecked => ShellSettings.powerProfileRemember = nextChecked
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
                id: _vitals
                active: root.active
                dividerIndent: root._rowTextX
                width: parent.width
                batteryExpanded: root._picker === "battery"
                onBatteryActivated: root._togglePicker("battery")
                // a UPower restart takes the row away: its details close with it, or Escape had nothing left to shut
                onBatteryOpenableChanged: if (!batteryOpenable && root._picker === "battery") root._closePicker()
            }
        }
    }
}
