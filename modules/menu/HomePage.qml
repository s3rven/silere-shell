pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight
    onPageShown: {
        _mediaUnload.stop()
        _mediaSection._mediaLoaded = Media.shown
        _settleMedia()
    }
    onPageHidden: {
        _picker = ""
        _volumeRow.open = false
        _brightnessRow.open = false
        if (ShellSettings.reduceMotion) _mediaSection._mediaLoaded = false
        else _mediaUnload.restart()
        _settleMedia()
    }

    function _settleMedia(): void {
        const card = _mediaLoader.item
        if (card) card.settleMediaVisual()
    }

    property string _picker: ""
    readonly property int _sectionGap: 12
    readonly property int _itemGap: 8
    readonly property bool _wifiAvailable: Network.toolAvailable && Network.hasWifiDevice
    readonly property bool _btAvailable: Bluetooth.available
    readonly property bool _brightnessAvailable: Brightness.controllable
    readonly property bool _wifiPickerOpen: _picker === "wifi"
    readonly property bool _btPickerOpen: _picker === "bt"

    function _togglePicker(which: string): void {
        if (_picker === which) {
            root._closePicker()
            return
        }
        const pickerMoved = root._closePicker()
        const volumeMoved = _volumeRow.closeInline()
        const brightnessMoved = _brightnessRow.closeInline()
        _picker = which
        if (pickerMoved || volumeMoved || brightnessMoved) {
            const fromPointer = which === "wifi" ? _wifiRow.pointerFocusActive
                : which === "bt" ? _btRow.pointerFocusActive
                : _nightRow.pointerFocusActive
            root._focusPickerTrigger(which, fromPointer)
        }
    }

    function _focusPickerTrigger(which: string, fromPointer): void {
        const trigger = which === "wifi" ? _wifiRow
            : which === "bt" ? _btRow : _nightRow
        if (!trigger) return
        if (fromPointer === true) trigger.focusFromPointer()
        else trigger.focusFromKeyboard()
    }

    function _closePicker(): bool {
        const which = root._picker
        if (which === "") return false
        const focusWindow = root.Window.window
        const focusedItem = focusWindow ? focusWindow.activeFocusItem : null
        const ownsFocus = which === "wifi" ? ItemTree.isInside(focusedItem, _wifiPicker)
            : which === "bt" ? ItemTree.isInside(focusedItem, _btPicker)
            : ItemTree.isInside(focusedItem, _nightPicker)
        if (ownsFocus) root._focusPickerTrigger(which,
            focusedItem && focusedItem.pointerFocusActive === true)
        root._picker = ""
        return ownsFocus
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
    Connections {
        target: Bluetooth
        enabled: root.active
        function onEnabledChanged() {
            if (root._picker === "bt" && !Bluetooth.enabled) root._closePicker()
        }
    }
    Connections {
        target: NightLight
        enabled: root.active
        function onEnabledChanged() {
            if (root._picker === "nightlight" && !NightLight.enabled) root._closePicker()
        }
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            id: _header
            width: parent.width
            height: 4 * Math.ceil((_dayLine.implicitHeight + 2 + _metaLine.implicitHeight) / 4)

            ShellText {
                id: _dayLine
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                text: DateTime.cachedWeekday
                color: Theme.text
                font.pixelSize: Settings.fontSize + 5
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            ShellText {
                id: _metaLine
                anchors.left: parent.left
                anchors.right: _uptimeRow.visible ? _uptimeRow.left : parent.right
                anchors.rightMargin: 12
                anchors.top: _dayLine.bottom
                anchors.topMargin: 2
                text: DateTime.cachedWeek.length > 0
                    ? DateTime.cachedMonthDay + " · Week " + DateTime.cachedWeek
                    : DateTime.cachedMonthDay
                color: Theme.withAlpha(Theme.subtext, 0.78)
                font.pixelSize: Settings.fontLabel
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            ShellText {
                id: _uptimeRow
                anchors.right: parent.right
                anchors.verticalCenter: _metaLine.verticalCenter
                visible: SysInfo.uptimeSecs > 0
                text: "up " + SysInfo.uptimeLabel
                color: Theme.withAlpha(Theme.subtext, 0.62)
                font.pixelSize: Settings.fontLabel
                font.weight: Font.Medium
            }
        }

        Item {
            width: 1
            height: Media.shown ? root._sectionGap : 0
            Disclosure on height { expanded: Media.shown }
        }

        Item {
            id: _mediaSection
            width: parent.width
            property bool _mediaLoaded: false

            Component.onCompleted: _mediaLoaded = root.active && Media.shown
            Connections {
                target: Media
                enabled: root.active
                function onShownChanged() {
                    if (Media.shown) {
                        _mediaUnload.stop()
                        _mediaSection._mediaLoaded = true
                    } else if (ShellSettings.reduceMotion) {
                        _mediaSection._mediaLoaded = false
                    } else {
                        _mediaUnload.restart()
                    }
                }
            }
            Timer {
                id: _mediaUnload
                interval: Motion.fast + Motion.ms(30)
                onTriggered: if (!root.active || !Media.shown)
                    _mediaSection._mediaLoaded = false
            }

            // snap to 4 logical px: unaligned offsets double their 1px borders under fractional scaling
            height: Media.shown && _mediaLoader.item
                ? 4 * Math.ceil((_mediaLoader.item.height + 10) / 4) : 0
            clip: true

            Disclosure on height { expanded: Media.shown }

            Loader {
                id: _mediaLoader
                width: parent.width
                active: _mediaSection._mediaLoaded
                sourceComponent: Component { MediaCard {} }
            }
        }

        SectionLabel {
            label: Audio.ready && root._brightnessAvailable ? "Audio & Display"
                 : root._brightnessAvailable ? "Display"
                 : "Audio"
            visible: Audio.ready || root._brightnessAvailable
        }
        SettingsCard {
            id: _primaryControls
            visible: Audio.ready || root._brightnessAvailable

            VolumeRow {
                id: _volumeRow
                visible: Audio.ready
                reserveExpandSlot: _brightnessRow.visible && Brightness.devices.length > 1
                onOpenChanged: if (open) {
                    const pickerMoved = root._closePicker()
                    const brightnessMoved = _brightnessRow.closeInline()
                    if (pickerMoved || brightnessMoved) _volumeRow.focusPrimary()
                }
            }
            BrightnessRow {
                id: _brightnessRow
                visible: root._brightnessAvailable
                reserveExpandSlot: _volumeRow.visible && Audio.sinkCount > 1
                onOpenChanged: if (open) {
                    const pickerMoved = root._closePicker()
                    const volumeMoved = _volumeRow.closeInline()
                    if (pickerMoved || volumeMoved) _brightnessRow.focusPrimary()
                }
            }
        }
        SectionLabel {
            label: "Connectivity"
            visible: root._wifiAvailable || root._btAvailable
        }
        SettingsCard {
            visible: root._wifiAvailable || root._btAvailable

            ControlRow {
                id: _wifiRow
                visible: root._wifiAvailable
                readonly property bool _ethActive: Network.connected && Network.deviceType === "ethernet"
                active: Network.wifiEnabled
                glyph: Network.wifiEnabled
                    ? (Network.isWifi && Network.connected ? Network.signalGlyph(Network.signalStrength) : "󰤨")
                    : "󰤭"
                title: "Wi-Fi"
                status: Network.wifiEnabled && Network.isWifi && Network.connected ? Network.connectionName
                      : Network.wifiConnecting.length > 0 ? "Connecting to " + Network.wifiConnecting
                      : Network.wifiError.length > 0 ? "Couldn't connect to " + Network.wifiError
                      : _ethActive ? "Ethernet active"
                      : Network.wifiEnabled ? "Not connected"
                      : "Off"
                showSwitch: true
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
                id: _btRow
                visible: root._btAvailable
                active: Bluetooth.enabled
                glyph: Bluetooth.enabled ? "󰂯" : "󰂲"
                title: "Bluetooth"
                status: Bluetooth.connectedCount > 0
                    ? (Bluetooth.connectedCount === 1
                        ? Bluetooth.connectedName + (Bluetooth.connectedBattery >= 0 ? "  " + Bluetooth.connectedBattery + "%" : "")
                        : Bluetooth.connectedCount + " connected")
                    : Bluetooth.enabled ? "Not connected" : "Off"
                showSwitch: true
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
                    }
                }
            }
        }

        SectionLabel { label: "Controls" }
        SettingsCard {
            ControlRow {
                id: _nightRow
                visible: NightLight.toolAvailable
                active: NightLight.enabled
                glyph: NightLight.enabled ? "󰖔" : "󰖙"
                title: "Night Light"
                status: NightLight.lastError.length > 0 ? NightLight.lastError
                      : NightLight.enabled ? NightLight.temperature + "K" : NightLight.recommendLabel
                accentColor: NightLight.lastError.length > 0 ? Theme.error : Theme.warning
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
                                glyph: "󰔄"
                                label: "Temperature"
                                displayValue: ShellSettings.nightLightTemp + "K"
                                value: ShellSettings.nightLightTemp
                                min: 1000; max: 6500; step: 100
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
                id: _powerRow
                visible: PowerProfiles.available
                available: PowerProfiles.profile !== ""
                active: PowerProfiles.profile !== "" && PowerProfiles.profile !== "balanced"
                glyph: PowerProfiles.glyph
                title: "Power Mode"
                valueText: PowerProfiles.profile !== "" ? PowerProfiles.label
                         : PowerProfiles.syncing ? "Checking…"
                         : "Unavailable"
                onActivated: PowerProfiles.cycle()
            }

            ControlRow {
                id: _lockRow
                visible: SystemTools.commandAvailable(Settings.lockCommand)
                glyph: "󰍁"
                title: "Lock"
                onActivated: {
                    MenuState.close()
                    SystemTools.runOrNotify(Settings.lockCommand, "Lock failed")
                }
            }
        }

        SectionLabel { label: "System" }
        VitalsStrip {
            active: root.active
            width: parent.width
        }

        Item { width: 1; height: root._itemGap }
    }
}
