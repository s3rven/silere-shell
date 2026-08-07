pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
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
    }
    onPageHidden: {
        _picker = ""
        _volumeRow.open = false
        _brightnessRow.open = false
        if (ShellSettings.reduceMotion) _mediaSection._mediaLoaded = false
        else _mediaUnload.restart()
    }

    property string _picker: ""
    readonly property int _sectionGap: 12
    readonly property int _itemGap: 8
    readonly property bool _wifiAvailable: Network.toolAvailable && Network.hasWifiDevice
    readonly property bool _btAvailable: Bluetooth.available
    readonly property bool _brightnessAvailable: Brightness.controllable
    readonly property bool _wifiPickerOpen: _picker === "wifi"
    readonly property bool _btPickerOpen: _picker === "bt"

    function _shq(s): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function _runPower(command, failTitle): void {
        if (!command || command.length === 0) return
        if (!SystemTools.hasNotifySend) {
            Quickshell.execDetached(command)
            return
        }
        const note = "notify-send --urgency=critical --app-name=silere-shell " +
            root._shq(failTitle) + " " + root._shq("It may require authorization or be blocked by a running task.")
        const argv = ["bash", "-c", '"$@" || ' + note, "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        Quickshell.execDetached(argv)
    }

    function _togglePicker(which: string): void {
        _picker = (_picker === which ? "" : which)
        if (_picker !== "") {
            _volumeRow.open = false
            _brightnessRow.open = false
        }
    }

    function dismissInline(): bool {
        if (_volumeRow.open) {
            _volumeRow.open = false
            return true
        }
        if (_brightnessRow.open) {
            _brightnessRow.open = false
            return true
        }
        if (_picker === "") return false
        _picker = ""
        return true
    }

    Connections {
        target: Network
        enabled: root.active
        function onWifiEnabledChanged() { if (root._picker === "wifi" && !Network.wifiEnabled) root._picker = "" }
    }
    Connections {
        target: Bluetooth
        enabled: root.active
        function onEnabledChanged() { if (root._picker === "bt" && !Bluetooth.enabled) root._picker = "" }
    }
    Connections {
        target: NightLight
        enabled: root.active
        function onEnabledChanged() { if (root._picker === "nightlight" && !NightLight.enabled) root._picker = "" }
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
                sourceComponent: Component {
                    ClippingRectangle {
                id: _mediaCard
                width: parent ? parent.width : 0
                readonly property int _seekBlock: Media.hasPosition ? 26 : 0
                // 4px multiple: an odd height lands the bottom border on a half physical pixel and doubles it
                height: 4 * Math.ceil(Math.max(168,
                    16 + _controlsRow.height + _seekBlock + 12 + _mediaCol.implicitHeight + 26) / 4)
                radius: Theme.radiusCard
                color: Theme.menuCard
                opacity: Media.shown ? 1.0 : 0.0
                visible: opacity > 0.01

                function _focusPlayer(): void {
                    MenuState.close()
                    HyprActions.focusMediaPlayer(Media.playerName, Media.title)
                }

                OutlineBorder {
                    // above the album art and its scrim: both fill the card and are declared later
                    z: 1
                    radius: _mediaCard.radius
                    outlineWidth: _playerTarget.activeFocus ? 2 : 1
                    outlineColor: _playerTarget.activeFocus
                        ? Theme.withAlpha(Theme.accent, Theme.focusRingAlpha) : Theme.menuCardBorder
                }

                // fade only: a scale leg ran as a third competing animation and resampled NativeRendering text off-pixel
                Disclosure on opacity { expanded: Media.shown; enterEasing: Easing.OutCubic }

                // on reappear, text may be stranded at opacity 0 by a crossfade interrupted while hidden
                Connections {
                    target: Media
                    function onShownChanged() {
                        if (Media.shown) { _textFade.stop(); _mediaCol.opacity = 1.0; _mediaCol._slide = 0 }
                    }
                }

                Item {
                    id: _art
                    anchors.fill: parent
                    // the scrim over this is uniform by contract, so the art's own ceiling is what stops highlights punching through the title
                    readonly property real maxAlpha: 0.64
                    property bool _useA: true
                    property string _curUrl: ""
                    property var _pendingLayer: null
                    readonly property real shownAlpha: Math.max(_artA.opacity, _artB.opacity)

                    function _apply() {
                        const url = Media.stableArtUrl
                        if (url === _curUrl) return
                        _curUrl = url
                        _pendingLayer = null
                        _artRetry.stop()
                        if (!url || url.length === 0) {
                            _artIn.stop(); _artInScale.stop(); _artOut.stop()
                            _artA.opacity = 0; _artA.scale = 1.0; _artA.source = ""
                            _artB.opacity = 0; _artB.scale = 1.0; _artB.source = ""
                            return
                        }
                        const idle = _useA ? _artB : _artA
                        _pendingLayer = idle
                        // re-assigning an identical source is a no-op in Qt; clear first so an error retry reloads
                        if (String(idle.source) === url) idle.source = ""
                        idle.source = url
                    }

                    function _releaseLayer(img) {
                        const current = _useA ? _artA : _artB
                        if (!img || img === current || img === _pendingLayer) return
                        img.opacity = 0
                        img.scale = 1.0
                        img.source = ""
                    }

                    property int _retries: 0
                    Timer {
                        id: _artRetry
                        interval: 2500
                        onTriggered: { if (!MenuState.open) return; _art._curUrl = ""; _art._apply() }
                    }
                    function _failed(img) {
                        if (img !== _pendingLayer) return
                        _pendingLayer = null
                        _curUrl = ""
                        if (MenuState.open && _retries < 3) { _retries++; _artRetry.restart() }
                    }

                    function _promote(img, isA) {
                        // object identity, not URL compare, Qt normalises URLs (e.g. %20)
                        if (img !== _pendingLayer || img.status !== Image.Ready) return
                        _pendingLayer = null
                        _artRetry.stop()
                        _retries = 0
                        _useA = isA
                        const outgoing = isA ? _artB : _artA
                        if (ShellSettings.reduceMotion) {
                            img.scale = 1.0; img.opacity = maxAlpha; outgoing.opacity = 0
                            _releaseLayer(outgoing)
                            return
                        }
                        img.scale = 1.06
                        _artIn.target = img;      _artIn.restart()
                        _artInScale.target = img; _artInScale.restart()
                        _artOut.target = outgoing; _artOut.to = 0; _artOut.restart()
                    }

                    Connections { target: Media; function onStableArtUrlChanged() { _art._retries = 0; _art._apply() } }
                    Connections { target: MenuState; function onOpenChanged() { if (MenuState.open) { _art._retries = 0; _art._apply() } } }
                    Component.onCompleted: _apply()

                    Image {
                        id: _artA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // uncached: caching keeps every past track's 512² decode for the whole session
                        cache: false
                        sourceSize.width:  512
                        sourceSize.height: 512
                        opacity: 0
                        visible: opacity > 0.01
                        transformOrigin: Item.Center
                        onStatusChanged: status === Image.Error ? _art._failed(_artA) : _art._promote(_artA, true)
                    }
                    Image {
                        id: _artB
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width:  512
                        sourceSize.height: 512
                        opacity: 0
                        visible: opacity > 0.01
                        transformOrigin: Item.Center
                        onStatusChanged: status === Image.Error ? _art._failed(_artB) : _art._promote(_artB, false)
                    }

                    NumberAnimation { id: _artIn;      property: "opacity"; to: _art.maxAlpha; duration: Motion.ms(380); easing.type: Easing.OutCubic }
                    NumberAnimation { id: _artInScale; property: "scale";   to: 1.0;           duration: Motion.ms(520); easing.type: Easing.OutCubic }
                    NumberAnimation {
                        id: _artOut
                        property: "opacity"
                        duration: Motion.ms(300)
                        easing.type: Easing.OutCubic
                        onFinished: _art._releaseLayer(_artOut.target)
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: _art.shownAlpha > 0.01
                    color: Theme.withAlpha(_mediaCard.color, 0.72)
                }

                // down to the seek row, so the title and artist are part of the jump target
                MouseArea {
                    id: _playerTarget
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: _seek.top
                    cursorShape: Qt.PointingHandCursor
                    activeFocusOnTab: Media.available
                    Accessible.role: Accessible.Button
                    Accessible.name: Media.label.length > 0
                        ? "Focus media player for " + Media.label : "Focus media player"
                    Accessible.focusable: true
                    Accessible.onPressAction: _mediaCard._focusPlayer()
                    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) _mediaCard._focusPlayer(); event.accepted = true }
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _mediaCard._focusPlayer(); event.accepted = true }
                    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) _mediaCard._focusPlayer(); event.accepted = true }
                    onClicked: _mediaCard._focusPlayer()
                }

                Column {
                    id: _mediaCol
                    anchors {
                        left: parent.left; leftMargin: 16
                        right: parent.right; rightMargin: 16
                        bottom: _seek.top; bottomMargin: 12
                    }
                    spacing: 2
                    opacity: 1.0

                    property real _slide: 0
                    transform: Translate { y: _mediaCol._slide }

                    property string _shownIdentity: ""
                    property string _shownTitle:    ""
                    property string _shownArtist:   ""
                    Component.onCompleted: {
                        _shownIdentity = Media.identity
                        _shownTitle    = Media.title
                        _shownArtist   = Media.artist
                    }

                    readonly property string trackKey: Media.identity + "\u0000" + Media.title + "\u0000" + Media.artist
                    onTrackKeyChanged: {
                        if (ShellSettings.reduceMotion || (_shownTitle === "" && _shownArtist === "")) {
                            _shownIdentity = Media.identity
                            _shownTitle    = Media.title
                            _shownArtist   = Media.artist
                            opacity = 1.0
                            _slide  = 0
                            return
                        }
                        _textFade.restart()
                    }

                    SequentialAnimation {
                        id: _textFade
                        NumberAnimation { target: _mediaCol; property: "opacity"; to: 0.0; duration: Motion.ms(110); easing.type: Easing.InCubic }
                        ScriptAction {
                            script: {
                                _mediaCol._shownIdentity = Media.identity
                                _mediaCol._shownTitle    = Media.title
                                _mediaCol._shownArtist   = Media.artist
                                _mediaCol._slide = 6
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: _mediaCol; property: "opacity"; to: 1.0; duration: Motion.ms(200); easing.type: Easing.OutCubic }
                            NumberAnimation { target: _mediaCol; property: "_slide";  to: 0;   duration: Motion.ms(260); easing.type: Easing.OutCubic }
                        }
                    }

                    ShellText {
                        id: _identityText
                        readonly property bool _switchable: Media.playerCount > 1
                        readonly property bool _switchHover: _switchable && _identitySwitch.containsMouse
                        readonly property bool _switchFocused: _switchable && _identityText.activeFocus

                        width: parent.width
                        visible: _mediaCol._shownIdentity.length > 0
                        text: _mediaCol._shownIdentity.toUpperCase()
                            + (_switchable ? "  󰅂" : "")
                        color: _switchFocused ? Theme.accent
                             : _switchHover   ? Theme.withAlpha(Theme.text, 0.78)
                                              : Theme.withAlpha(Theme.subtext, 0.62)
                        font.pixelSize: Settings.fontMicro
                        font.weight: Font.Medium
                        font.letterSpacing: 1.2
                        elide: Text.ElideRight
                        ColorFade on color {}

                        activeFocusOnTab: _switchable
                        Accessible.role: Accessible.Button
                        Accessible.name: "Switch media player"
                        Accessible.description: Media.identity
                        Accessible.focusable: _switchable
                        Accessible.onPressAction: Media.cyclePlayer()
                        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) Media.cyclePlayer(); event.accepted = true }
                        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) Media.cyclePlayer(); event.accepted = true }
                        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) Media.cyclePlayer(); event.accepted = true }

                        MouseArea {
                            id: _identitySwitch
                            enabled: _identityText._switchable
                            hoverEnabled: enabled
                            y: -6
                            width: Math.min(parent.paintedWidth, parent.width)
                            height: parent.height + 12
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Media.cyclePlayer()
                        }
                    }

                    Item { width: 1; height: 4; visible: _identityText.visible }

                    ShellText {
                        id: _titleText
                        width: parent.width
                        text: _mediaCol._shownTitle.length > 0 ? _mediaCol._shownTitle
                            : _mediaCol._shownArtist.length > 0 ? _mediaCol._shownArtist
                            : _mediaCol._shownIdentity.length > 0 ? _mediaCol._shownIdentity
                            : "Media"
                        color: Theme.text
                        font.pixelSize: Settings.fontSize + 3
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Item { width: 1; height: 2; visible: _artistText.visible }

                    ShellText {
                        id: _artistText
                        width: parent.width
                        visible: _mediaCol._shownTitle.length > 0 && _mediaCol._shownArtist.length > 0
                        text: _mediaCol._shownArtist
                        color: Theme.withAlpha(Theme.subtext, 0.75)
                        font.pixelSize: Settings.fontSize
                        elide: Text.ElideRight
                    }
                }

                Item {
                    id: _seek
                    visible: Media.hasPosition
                    anchors {
                        left:  parent.left;  leftMargin:  16
                        right: parent.right; rightMargin: 16
                        bottom: _controlsRow.top
                        bottomMargin: visible ? 12 : 0
                    }
                    height: visible ? 14 : 0

                    activeFocusOnTab: Media.canSeek
                    Accessible.role: Accessible.Slider
                    Accessible.name: "Seek"
                    Accessible.description: Media.formatTime(Media.positionNow) + " of " + Media.formatTime(Media.length)
                    Accessible.focusable: Media.canSeek
                    Accessible.onIncreaseAction: if (Media.canSeek) _seekTrack.nudge(1, 1)
                    Accessible.onDecreaseAction: if (Media.canSeek) _seekTrack.nudge(-1, 1)
                    Keys.onPressed: event => _seekTrack.handleKey(event)

                    ShellText {
                        id: _elapsedLabel
                        width: _totalLabel.implicitWidth
                        horizontalAlignment: Text.AlignRight
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Media.formatTime(_seekTrack.dragging ? _seekTrack.shownValue * Media.length : Media.positionNow)
                        color:          Theme.withAlpha(Theme.text, 0.62)
                        font.pixelSize: Settings.fontMicro
                    }
                    ShellText {
                        id: _totalLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Media.formatTime(Media.length)
                        color:          Theme.withAlpha(Theme.text, 0.55)
                        font.pixelSize: Settings.fontMicro
                    }

                    SliderTrack {
                        id: _seekTrack
                        anchors.left:  _elapsedLabel.right; anchors.leftMargin:  8
                        anchors.right: _totalLabel.left;    anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 12

                        interactive: Media.canSeek
                        focused:     _seek.activeFocus
                        showThumb:   Media.canSeek
                        hoverGrow:   false
                        animate:     false
                        commitOnRelease: true
                        trackColor:  Theme.withAlpha(Theme.text, 0.20)
                        value: Media.positionRatio
                        onChanged: value => { if (Media.canSeek) Media.seekToRatio(value) }
                    }
                }

                Row {
                    id: _controlsRow
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom; bottomMargin: 16
                    }
                    spacing: 24

                    MediaButton {
                        glyph: "󰒮"
                        accessibleName: "Previous track"
                        available: Media.canGoPrevious
                        onTriggered: Media.previous()
                    }

                    Item {
                        id: _playBtn
                        readonly property bool _on: Media.canTogglePlaying
                        width: 56; height: 40
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: _playBtn._on ? 1.0 : 0.25
                        scale: _playT.pressed ? 0.94 : 1.0
                        transformOrigin: Item.Center
                        MotionBehavior on opacity {
                            NumberAnimation { duration: Motion.fast }
                        }
                        MotionBehavior on scale   {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                        activeFocusOnTab: _playBtn._on
                        Accessible.role: Accessible.Button
                        Accessible.name: Media.playing ? "Pause" : "Play"
                        Accessible.onPressAction: if (_playBtn._on) Media.togglePlay()
                        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }
                        Keys.onReturnPressed: event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }
                        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }

                        HoverHandler { id: _playH; enabled: _playBtn._on; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { id: _playT; enabled: _playBtn._on; onTapped: Media.togglePlay() }

                        Rectangle {
                            id: _playFill
                            anchors.fill: parent
                            radius: Theme.radiusControl
                            antialiasing: true
                            color: _playT.pressed ? Theme.mix(Theme.menuControl, Theme.accent, 0.18)
                                : _playH.hovered ? Theme.mix(Theme.menuControl, Theme.accent, 0.10)
                                : Theme.menuControl
                            ColorFade on color {}

                            OutlineBorder {
                                radius: _playFill.radius
                                outlineWidth: _playBtn.activeFocus ? 2 : 1
                                outlineColor: _playBtn.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
                                    : Theme.menuControlLine
                                ColorFade on outlineColor {}
                            }
                        }
                        ShellText {
                            id: _playGlyph
                            anchors.centerIn: parent
                            property string shown: ""
                            readonly property string target: Media.playing ? "󰏤" : "󰐊"
                            property bool _ready: false
                            text: shown
                            color: _playH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.8)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize + 10
                            transformOrigin: Item.Center
                            ColorFade on color {}

                            Component.onCompleted: { shown = target; _ready = true }
                            onTargetChanged: {
                                if (!_ready || ShellSettings.reduceMotion) { shown = target; return }
                                _playStamp.restart()
                            }
                            SequentialAnimation {
                                id: _playStamp
                                NumberAnimation { target: _playGlyph; property: "scale"; to: 0.72; duration: Motion.instant; easing.type: Easing.InCubic }
                                ScriptAction    { script: _playGlyph.shown = _playGlyph.target }
                                NumberAnimation { target: _playGlyph; property: "scale"; from: 0.72; to: 1.0; duration: Motion.fast; easing.type: Easing.OutQuart }
                            }
                        }
                    }

                    MediaButton {
                        glyph: "󰒭"
                        accessibleName: "Next track"
                        available: Media.canGoNext
                        onTriggered: Media.next()
                    }
                }
                    }
                }
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
                    root._picker = ""
                    _brightnessRow.open = false
                }
            }
            BrightnessRow {
                id: _brightnessRow
                visible: root._brightnessAvailable
                reserveExpandSlot: _volumeRow.visible && Audio.sinkCount > 1
                onOpenChanged: if (open) {
                    root._picker = ""
                    _volumeRow.open = false
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
                open: root._wifiPickerOpen
                gap: 0
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
                open: root._btPickerOpen
                gap: 0
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
                status: NightLight.enabled ? NightLight.temperature + "K" : NightLight.recommendLabel
                accentColor: Theme.warning
                showSwitch: true
                expandable: NightLight.enabled
                expanded: root._picker === "nightlight"
                onActivated: NightLight.toggle()
                onExpandToggled: root._togglePicker("nightlight")
            }

            CollapsibleSection {
                expanded: root._picker === "nightlight"
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

            ControlRow {
                id: _dndRow
                active: Notifications.dnd
                glyph: Notifications.effectiveDnd || Notifications.fullscreenSilenced ? "󰂛" : "󰂚"
                title: "Do Not Disturb"
                status: Notifications.effectiveDnd && !Notifications.dnd ? "Quiet hours"
                    : Notifications.fullscreenSilenced ? "Fullscreen"
                    : ""
                showSwitch: true
                badgeCount: Notifications.effectiveDnd || Notifications.fullscreenSilenced ? Notifications.missedCount : 0
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
                readonly property bool lockAvailable: {
                    const cmd = Settings.lockCommand
                    if (!cmd || cmd.length === 0) return false
                    if (String(cmd[0]) === "hyprlock") return SystemTools.hasHyprlock
                    return true
                }
                visible: lockAvailable
                glyph: "󰍁"
                title: "Lock"
                onActivated: {
                    MenuState.close()
                    root._runPower(Settings.lockCommand, "Lock failed")
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
