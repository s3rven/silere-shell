import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../bar/widgets"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight
    scaleFrom: 0.96
    enterFade: 160; enterScale: 210; exitFade: 110
    onPageHidden: {
        _picker = ""
        _volumeRow.open = false
    }

    property string _picker: ""   // "" | "wifi" | "bt" | "nightlight" — open inline list
    readonly property int _sectionGap: 12
    readonly property int _itemGap: 8

    function _togglePicker(which: string): void { _picker = (_picker === which ? "" : which) }

    // Escape steps back: close an open inline picker before the menu itself.
    function dismissInline(): bool {
        if (_picker === "") return false
        _picker = ""
        return true
    }

    // Fold a picker away if its radio/adapter is switched off underneath it.
    Connections {
        target: Network
        function onWifiEnabledChanged() { if (root._picker === "wifi" && !Network.wifiEnabled) root._picker = "" }
    }
    Connections {
        target: Bluetooth
        function onEnabledChanged() { if (root._picker === "bt" && !Bluetooth.enabled) root._picker = "" }
    }
    Connections {
        target: NightLight
        function onEnabledChanged() { if (root._picker === "nightlight" && !NightLight.enabled) root._picker = "" }
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            id: _header
            width: parent.width
            height: 40

            Text {
                id: _dayLine
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                text: DateTime.cachedWeekday
                color: Theme.text
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 5
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }

            Text {
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
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.weight: Font.Medium
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }

            Text {
                id: _uptimeRow
                anchors.right: parent.right
                anchors.verticalCenter: _metaLine.verticalCenter
                visible: SysInfo.uptimeSecs > 0
                text: "up " + SysInfo.uptimeLabel
                color: Theme.withAlpha(Theme.subtext, 0.62)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }

        // spacers are 4px multiples so card dividers below stay on the grid
        Item { width: 1; height: root._sectionGap }

        Item {
            id: _mediaSection
            width: parent.width
            // Snap to 4 logical px so rows below land on whole physical pixels
            // under fractional scaling — unaligned offsets double their 1px borders.
            height: Media.shown ? 4 * Math.ceil((_mediaCard.height + 10) / 4) : 0
            clip: true

            Behavior on height {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            ClippingRectangle {
                id: _mediaCard
                width: parent.width
                readonly property int _seekBlock: Media.hasPosition ? 26 : 0
                // Snap to a 4px multiple: an integer-but-odd height lands the bottom
                // border on a half physical pixel under fractional scaling and doubles it.
                height: 4 * Math.ceil(Math.max(168,
                    16 + _controlsRow.height + _seekBlock + 12 + _mediaCol.implicitHeight + 26) / 4)
                radius: 12
                color: Theme.menuCard
                // no stroke: a 1px border doubles on fractional displays, and the lit play button already signals playback
                border.width: 0
                opacity: Media.shown ? 1.0 : 0.0
                visible: opacity > 0.01
                scale: Media.shown ? 1.0 : 0.97
                transformOrigin: Item.Center

                Behavior on opacity {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 0.4 }
                }

                // on reappear, text may be stranded at opacity 0 by a crossfade interrupted while hidden
                Connections {
                    target: Media
                    function onShownChanged() {
                        if (Media.shown) { _textFade.stop(); _mediaCol.opacity = 1.0; _mediaCol._slide = 0 }
                    }
                }

                // Two layers cross-dissolve; debounce lives in Media.stableArtUrl.
                Item {
                    id: _art
                    anchors.fill: parent
                    readonly property real maxAlpha: 0.78
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
                            _artA.opacity = 0; _artB.opacity = 0
                            return
                        }
                        const idle = _useA ? _artB : _artA
                        _pendingLayer = idle
                        // re-assigning an identical source is a no-op in Qt; clear first so an error retry reloads
                        if (String(idle.source) === url) idle.source = ""
                        idle.source = url
                    }

                    // a failed fetch (network not up right after login) shouldn't strand the card
                    // artless till next track: retry a few times, then clear _curUrl so a later apply retries
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
                        // Object identity, not URL compare, Qt normalises URLs (e.g. %20).
                        if (img !== _pendingLayer || img.status !== Image.Ready) return
                        _pendingLayer = null
                        _artRetry.stop()
                        _retries = 0
                        _useA = isA
                        const outgoing = isA ? _artB : _artA
                        if (ShellSettings.reduceMotion) {
                            img.scale = 1.0; img.opacity = maxAlpha; outgoing.opacity = 0
                            return
                        }
                        img.scale = 1.06
                        _artIn.target = img;      _artIn.restart()
                        _artInScale.target = img; _artInScale.restart()
                        _artOut.target = outgoing; _artOut.to = 0; _artOut.restart()
                    }

                    // a genuinely new URL gets a fresh retry budget
                    Connections { target: Media; function onStableArtUrlChanged() { _art._retries = 0; _art._apply() } }
                    // catch up on changes while closed; reset retry budget so a failed art url retries on each open
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
                    NumberAnimation { id: _artOut;     property: "opacity"; duration: Motion.ms(300);     easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    text: "󰝚"
                    color: Theme.withAlpha(Theme.subtext, 0.22)
                    font.family: Settings.font
                    font.pixelSize: 56
                    renderType: Text.NativeRendering
                    opacity: Math.max(0, 1 - _art.shownAlpha / _art.maxAlpha)
                    visible: Media.shown && opacity > 0.01
                }

                // top scrim: fades art into the card colour so the clipped corner's stair-stepping doesn't read as a jagged edge; also lifts label contrast
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height * 0.26
                    visible: _art.shownAlpha > 0.01
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: _mediaCard.color }
                        GradientStop { position: 0.5; color: Theme.withAlpha(_mediaCard.color, 0.5) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.70
                    visible: _art.shownAlpha > 0.01
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.55; color: Theme.withAlpha(_mediaCard.color, 0.40) }
                        GradientStop { position: 0.78; color: Theme.withAlpha(_mediaCard.color, 0.90) }
                        GradientStop { position: 0.92; color: _mediaCard.color }
                        GradientStop { position: 1.0;  color: _mediaCard.color }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: parent.width * 0.32
                    visible: _art.shownAlpha > 0.01
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.withAlpha(_mediaCard.color, 0.42) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Loader {
                    id: _menuVizLoader
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(56, parent.height * 0.42)
                    active: root.active && MenuState.open && Media.shown && Media.playing
                        && Media.cavaReady && ShellSettings.mediaMenuVisualizer
                    opacity: _art.shownAlpha > 0.01 ? 0.16 : 0.26
                    visible: opacity > 0.01
                    sourceComponent: Component {
                        MediaVisualizer {
                            barName: ""
                            lowPower: true
                            styleOverride: "pulse"
                        }
                    }
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                    }
                }

                // art zone jumps to the player's window (like the bar widget's middle-click); ends at _mediaCol.top so it can't shadow seek/transport
                MouseArea {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: _mediaCol.top
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        MenuState.close()
                        HyprActions.focusMediaPlayer(Media.playerName, Media.title)
                    }
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

                    // held copies so a track change cross-dissolves instead of snapping
                    property string _shownIdentity: ""
                    property string _shownTitle:    ""
                    property string _shownArtist:   ""
                    Component.onCompleted: {
                        _shownIdentity = Media.identity
                        _shownTitle    = Media.title
                        _shownArtist   = Media.artist
                    }

                    readonly property string trackKey: Media.title + " • " + Media.artist
                    onTrackKeyChanged: {
                        // snap on reduce-motion and first population (held copies start empty); only crossfade between two real tracks
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
                            NumberAnimation { target: _mediaCol; property: "_slide";  to: 0;   duration: Motion.ms(280); easing.type: Easing.OutBack; easing.overshoot: 0.5 }
                        }
                    }

                    Text {
                        id: _identityText
                        width: parent.width
                        visible: _mediaCol._shownIdentity.length > 0
                        text: _mediaCol._shownIdentity.toUpperCase()
                        textFormat: Text.PlainText
                        color: Theme.withAlpha(Theme.subtext, 0.5)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 3
                        font.weight: Font.Medium
                        font.letterSpacing: 1.2
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Item { width: 1; height: 4; visible: _identityText.visible }

                    Text {
                        id: _titleText
                        width: parent.width
                        text: _mediaCol._shownTitle.length > 0 ? _mediaCol._shownTitle : (_mediaCol._shownArtist.length > 0 ? _mediaCol._shownArtist : "Nothing playing")
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize + 3
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Item { width: 1; height: 2; visible: _artistText.visible }

                    Text {
                        id: _artistText
                        width: parent.width
                        visible: _mediaCol._shownTitle.length > 0 && _mediaCol._shownArtist.length > 0
                        text: _mediaCol._shownArtist
                        textFormat: Text.PlainText
                        color: Theme.withAlpha(Theme.subtext, 0.75)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
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
                    Keys.onPressed: event => _seekTrack.handleKey(event)

                    Text {
                        id: _elapsedLabel
                        // Fixed width matching the total label so the track doesn't shift as digits change.
                        width: _totalLabel.implicitWidth
                        horizontalAlignment: Text.AlignRight
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Media.formatTime(_seekTrack.dragging ? _seekTrack.shownValue * Media.length : Media.positionNow)
                        color:          Theme.withAlpha(Theme.text, 0.62)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize - 3
                        renderType:     Text.NativeRendering
                    }
                    Text {
                        id: _totalLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Media.formatTime(Media.length)
                        color:          Theme.withAlpha(Theme.text, 0.42)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize - 3
                        renderType:     Text.NativeRendering
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
                        // Press feedback on the container so it composes with the glyph stamp.
                        scale: _playT.pressed ? 0.94 : 1.0
                        transformOrigin: Item.Center
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                        activeFocusOnTab: _playBtn._on
                        Accessible.role: Accessible.Button
                        Accessible.name: Media.playing ? "Pause" : "Play"
                        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }
                        Keys.onReturnPressed: event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }
                        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat && _playBtn._on) Media.togglePlay(); event.accepted = true }

                        HoverHandler { id: _playH; enabled: _playBtn._on; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { id: _playT; enabled: _playBtn._on; onTapped: Media.togglePlay() }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusControl
                            antialiasing: true
                            color: Media.playing || _playH.hovered || _playT.pressed
                                ? Theme.mix(Theme.menuControl, Theme.accent, _playT.pressed ? 0.38 : _playH.hovered ? 0.30 : 0.24)
                                : Theme.menuControl
                            border.width: 1
                            border.color: _playBtn.activeFocus ? Theme.withAlpha(Theme.accent, 0.82)
                                : Media.playing || _playH.hovered ? Theme.withAlpha(Theme.accent, 0.52)
                                : Theme.menuControlLine
                            Behavior on color        { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        }
                        Text {
                            id: _playGlyph
                            anchors.centerIn: parent
                            // held glyph so play⇄pause swaps with the stamp instead of a hard cut
                            property string shown: ""
                            readonly property string target: Media.playing ? "󰏤" : "󰐊"
                            property bool _ready: false
                            text: shown
                            color: (_playH.hovered || Media.playing) ? Theme.accent : Theme.withAlpha(Theme.accent, 0.9)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize + 10
                            renderType: Text.NativeRendering
                            transformOrigin: Item.Center
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

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

        // high-frequency controls up top; volume carries an inline output-device dropdown
        SettingsCard {
            id: _primaryControls
            visible: Audio.ready || Brightness.maxBrightness > 0
            rowDivider: "transparent"

            VolumeRow {
                id: _volumeRow
                visible: Audio.ready
            }
            QuickSlider {
                id: _brightnessSlider
                visible: Brightness.toolAvailable && Brightness.maxBrightness > 0
                glyph: Brightness.icon
                wheelKey: "brightness"
                accessibleName: "Brightness"
                value: Brightness.pendingPercent / 100
                valueText: Brightness.pendingPercent + "%"
                onMoved: (v) => Brightness.setPercent(Math.round(v * 100))
            }
        }
        SectionLabel {
            label: "Connectivity"
            visible: _wifiRow.visible || _btRow.visible
        }
        SettingsCard {
            visible: _wifiRow.visible || _btRow.visible

            ControlRow {
                id: _wifiRow
                readonly property bool _ethActive: Network.connected && Network.deviceType === "ethernet"
                visible: Network.toolAvailable && Network.hasWifiDevice
                active: Network.wifiEnabled
                glyph: Network.wifiEnabled ? "󰤨" : "󰤭"
                title: "Wi-Fi"
                status: Network.wifiEnabled && Network.isWifi && Network.connected ? Network.connectionName
                      : _ethActive ? "Ethernet active"
                      : Network.wifiEnabled ? "On"
                      : "Off"
                showSwitch: true
                expandable: Network.wifiEnabled
                expanded: root._picker === "wifi"
                onActivated: Network.toggleWifi()
                onExpandToggled: root._togglePicker("wifi")
            }

            ControlRow {
                id: _btRow
                visible: Bluetooth.available
                active: Bluetooth.enabled
                glyph: Bluetooth.enabled ? "󰂯" : "󰂲"
                title: "Bluetooth"
                status: Bluetooth.connectedCount > 0
                    ? (Bluetooth.connectedCount === 1
                        ? Bluetooth.connectedName + (Bluetooth.connectedBattery >= 0 ? "  " + Bluetooth.connectedBattery + "%" : "")
                        : Bluetooth.connectedCount + " connected")
                    : ""
                showSwitch: true
                expandable: Bluetooth.enabled
                expanded: root._picker === "bt"
                onActivated: Bluetooth.toggle()
                onExpandToggled: root._togglePicker("bt")
            }
        }

        Item {
            width: 1
            height: (root._picker === "wifi" || root._picker === "bt") ? root._itemGap : 0
            Behavior on height { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
        }
        CollapsibleSection {
            width: parent.width
            expanded: root._picker === "wifi"
            Loader {
                width: parent.width
                active: root._picker === "wifi"
                height: item ? item.implicitHeight : 0
                sourceComponent: Component {
                    WifiList {
                        width: parent.width
                        open: true
                    }
                }
            }
        }
        CollapsibleSection {
            width: parent.width
            expanded: root._picker === "bt"
            Loader {
                width: parent.width
                active: root._picker === "bt"
                height: item ? item.implicitHeight : 0
                sourceComponent: Component {
                    BluetoothList {
                        width: parent.width
                        open: true
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
                    onToggled: ShellSettings.nightLightAuto = !ShellSettings.nightLightAuto
                }
                SliderRow {
                    glyph: "󰔄"
                    label: ShellSettings.nightLightAuto ? "Temperature  ·  auto" : "Temperature"
                    enabled: !ShellSettings.nightLightAuto
                    displayValue: ShellSettings.nightLightTemp + "K"
                    value: ShellSettings.nightLightTemp
                    min: 1000; max: 6500; step: 100
                    glyphColor: Theme.withAlpha(Theme.warning, ShellSettings.nightLightAuto ? 0.45 : 0.85)
                    onChanged: (v) => { if (!ShellSettings.nightLightAuto) ShellSettings.nightLightTemp = v }
                }
                SunArc {
                    flat: true
                    // no canvas/buffer unless the dropdown is actually open on screen
                    shown: root._picker === "nightlight" && MenuState.open
                }
            }

            ControlRow {
                id: _dndRow
                active: Notifications.dnd
                glyph: Notifications.effectiveDnd ? "󰂛" : "󰂚"
                title: "Do Not Disturb"
                status: Notifications.effectiveDnd && !Notifications.dnd ? "Quiet hours" : ""
                showSwitch: true
                badgeCount: Notifications.effectiveDnd ? Notifications.missedCount : 0
                onActivated: Notifications.toggleDnd()
                onBadgeActivated: MenuState.showTab(2)
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
                    Quickshell.execDetached(Settings.lockCommand)
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
