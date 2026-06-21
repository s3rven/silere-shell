import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    transformOrigin: Item.Center

    property bool _entering: false
    property bool _firstActivation: true
    property string _picker: ""   // "" | "wifi" | "bt" — which inline list is open
    layer.enabled: _entering && !ShellSettings.reduceMotion

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
        function onDeviceTypeChanged()  { if (root._picker === "wifi" && Network.deviceType === "ethernet") root._picker = "" }
    }
    Connections {
        target: Bluetooth
        function onEnabledChanged() { if (root._picker === "bt" && !Bluetooth.enabled) root._picker = "" }
    }
    Connections {
        target: NightLight
        function onEnabledChanged() { if (root._picker === "nightlight" && !NightLight.enabled) root._picker = "" }
    }

    Component.onCompleted: opacity = root.active ? 1.0 : 0.0

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (root.opacity < 0.001) root.scale = 0.96
            _enter.restart()
            if (_firstActivation) {
                _firstActivation = false
                _cpuGauge.animateIn(80)
                _memGauge.animateIn(160)
                _diskGauge.animateIn(240)
                _battGauge.animateIn(320)
            }
        } else {
            _enter.stop()
            _exit.restart()
            _picker = ""
        }
    }

    ParallelAnimation {
        id: _enter
        onStarted: root._entering = true
        onStopped: root._entering = false
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(160); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale";   to: 1.0; duration: Motion.ms(210); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(110); easing.type: Easing.InCubic }
        ScriptAction { script: { root.scale = 1.0 } }
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        // spacers are 4px multiples so card dividers below stay on the grid
        Item { width: 1; height: 8 }

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
                readonly property int _seekBlock: Media.hasPosition ? _seek.height + 12 : 0
                height: Math.round(Math.max(180,
                    16 + _controlsRow.height + _seekBlock + 12 + _mediaCol.implicitHeight + 26))
                radius: 12
                contentUnderBorder: true
                color: Theme.mix(Theme.surface, Theme.subtext, 0.06)
                border.width: 1
                border.color: Media.playing
                    ? Theme.withAlpha(Theme.accent, 0.20)
                    : Theme.withAlpha(Theme.subtext, 0.10)
                Behavior on border.color { ColorAnimation { duration: Motion.medium } }
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

                // When the card re-appears, make sure the text wasn't stranded at
                // opacity 0 by a crossfade interrupted mid-flight while hidden.
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
                            _artA.opacity = 0; _artB.opacity = 0
                            return
                        }
                        const idle = _useA ? _artB : _artA
                        _pendingLayer = idle
                        // re-assigning an identical source is a no-op in Qt; clear
                        // first so an error retry actually reloads
                        if (String(idle.source) === url) idle.source = ""
                        idle.source = url
                    }

                    // A failed fetch (network not up yet right after login/restart)
                    // must not strand the card artless until the next track: retry
                    // a few times, then leave _curUrl cleared so any later apply
                    // (reopen, track change) tries again.
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
                    // catch up on whatever changed while closed (_curUrl makes this idempotent)
                    Connections { target: MenuState; function onOpenChanged() { if (MenuState.open) _art._apply() } }
                    Component.onCompleted: _apply()

                    Image {
                        id: _artA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
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
                        cache: true
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

                // Placeholder shown when there's no cover art.
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

                // Top vignette, frames the art against the rounded top edge.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height * 0.22
                    visible: _art.shownAlpha > 0.01
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Theme.withAlpha(_mediaCard.color, 0.45) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // Bottom scrim, cinematic grounding for the text/controls: holds
                // transparent up top, then ramps hard to solid in the lower third.
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

                // Narrow left feather, asymmetric lift without flattening the art.
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

                // Art zone (above the text block) jumps to the player's window,
                // same as the bar widget's middle-click. Ends at _mediaCol.top so
                // it can't shadow the seek bar or transport controls.
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

                    // Held copies so a track change cross-dissolves instead of
                    // snapping mid-fade.
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
                        // Snap on reduce-motion and on first population (held copies
                        // start empty); only crossfade between two genuine tracks.
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

                    property bool _dragging: false
                    property real _dragRatio: 0
                    readonly property real _ratio: _dragging ? _dragRatio : Media.positionRatio

                    function _nudge(dir: int): void {
                        if (!Media.canSeek) return
                        Media.seekToRatio(Math.max(0, Math.min(1, Media.positionRatio + dir * 0.05)))
                    }

                    activeFocusOnTab: Media.canSeek
                    Accessible.role: Accessible.Slider
                    Accessible.name: "Seek"
                    Accessible.description: Media.formatTime(Media.positionNow) + " of " + Media.formatTime(Media.length)
                    Keys.onLeftPressed:  _seek._nudge(-1)
                    Keys.onDownPressed:  _seek._nudge(-1)
                    Keys.onRightPressed: _seek._nudge(1)
                    Keys.onUpPressed:    _seek._nudge(1)

                    Text {
                        id: _elapsedLabel
                        // Fixed width matching the total label so the track doesn't shift as digits change.
                        width: _totalLabel.implicitWidth
                        horizontalAlignment: Text.AlignRight
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Media.formatTime(_seek._dragging ? _seek._dragRatio * Media.length : Media.positionNow)
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

                    Item {
                        id: _track
                        anchors.left:  _elapsedLabel.right; anchors.leftMargin:  8
                        anchors.right: _totalLabel.left;    anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 12

                        Rectangle {
                            id: _trackBg
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 3; radius: 1.5
                            antialiasing: true
                            color: Theme.withAlpha(Theme.text, 0.20)

                            Rectangle {
                                width:  _seek._ratio <= 0 ? 0 : Math.max(parent.radius * 2, parent.width * _seek._ratio)
                                height: parent.height; radius: parent.radius
                                antialiasing: true
                                clip: true

                                property real _shimmerPhase: 0

                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.accent, 0.68) }
                                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.accent, 0.92) }
                                }

                                Rectangle {
                                    visible: !ShellSettings.reduceMotion
                                    x: -36 + parent._shimmerPhase * (parent.width + 36)
                                    width: 36; height: parent.height
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Theme.withAlpha(Theme.text, 0.30) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                }

                                // root.active, not MenuState.open: the page keeps ticking
                                // invisibly behind another tab otherwise.
                                SequentialAnimation on _shimmerPhase {
                                    running: root.active && Media.playing && !ShellSettings.reduceMotion
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: 1; duration: 1400; easing.type: Easing.Linear }
                                    PauseAnimation  { duration: 1200 }
                                }

                                Behavior on width {
                                    enabled: !_seek._dragging && !ShellSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Rectangle {
                            id: _seekThumb
                            visible: Media.canSeek
                            width: 10; height: 10; radius: 5
                            antialiasing: true
                            x: _seek._ratio * (_track.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            color: _trackMa.pressed ? Theme.accent : Theme.text
                            scale: (_trackHover.hovered || _trackMa.pressed || _seek.activeFocus) ? 1.0 : 0.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on x {
                                // Skip the per-tick glide while the thumb is hidden; it only
                                // needs to animate when actually visible (hover/drag/focus).
                                enabled: !_seek._dragging && !ShellSettings.reduceMotion && (_trackHover.hovered || _trackMa.pressed || _seek.activeFocus)
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                        }

                        HoverHandler { id: _trackHover; enabled: Media.canSeek; cursorShape: Qt.PointingHandCursor }

                        MouseArea {
                            id: _trackMa
                            anchors.fill: parent
                            anchors.topMargin: -10; anchors.bottomMargin: -10
                            enabled: Media.canSeek
                            preventStealing: true
                            function _ratioAt(px) { return _track.width > 0 ? Math.max(0, Math.min(1, px / _track.width)) : 0 }
                            onPressed:         (m) => { _seek._dragging = true; _seek._dragRatio = _ratioAt(m.x) }
                            onPositionChanged: (m) => { if (pressed) _seek._dragRatio = _ratioAt(m.x) }
                            onReleased:        { Media.seekToRatio(_seek._dragRatio); _seek._dragging = false }
                            onCanceled:        _seek._dragging = false
                        }
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
                        available: Media.player ? Media.player.canGoPrevious : false
                        onTriggered: Media.previous()
                    }

                    Item {
                        id: _playBtn
                        readonly property bool _on: Media.player && Media.player.canTogglePlaying
                        width: 48; height: 48
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: _playBtn._on ? 1.0 : 0.25
                        // Press feedback on the container so it composes with the glyph stamp.
                        scale: _playT.pressed ? 0.82 : 1.0
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
                            anchors.centerIn: parent
                            width: 48; height: 48; radius: 24
                            antialiasing: true
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.accent, (_playH.hovered || _playBtn.activeFocus) ? 0.0 : 0.22)
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 48; height: 48; radius: 24
                            antialiasing: true
                            color: Theme.withAlpha(Theme.accent, _playT.pressed ? 0.26 : 0.16)
                            opacity: (_playH.hovered || _playT.pressed || _playBtn.activeFocus) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on color   { ColorAnimation  { duration: Motion.fast } }
                        }
                        Text {
                            id: _playGlyph
                            anchors.centerIn: parent
                            // Held glyph so play⇄pause swaps with the stamp instead
                            // of a hard cut.
                            property string shown: ""
                            readonly property string target: Media.playing ? "󰏤" : "󰐊"
                            property bool _ready: false
                            text: shown
                            color: _playH.hovered ? Theme.accent : Theme.withAlpha(Theme.accent, 0.9)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize + 16
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
                        available: Media.player ? Media.player.canGoNext : false
                        onTriggered: Media.next()
                    }
                }
            }
        }

        Grid {
            id: _toggleGrid
            width: parent.width
            columns: 2
            columnSpacing: 6
            rowSpacing: 8   // 4px multiple (tiles are 56), keeps rows below on the grid
            readonly property real cellW: (width - columnSpacing) / 2

            QuickToggleTile {
                width: _toggleGrid.cellW
                available: NightLight.toolAvailable
                active: NightLight.enabled
                activeGlyph: "󰖔"
                inactiveGlyph: "󰖙"
                title: "Night Light"
                status: !NightLight.toolAvailable ? "hyprsunset missing"
                      : NightLight.enabled ? NightLight.temperature + "K" : NightLight.recommendLabel
                accentColor: Theme.warning
                expandable: NightLight.toolAvailable && NightLight.enabled
                expanded: root._picker === "nightlight"
                onToggled: NightLight.toggle()
                onExpandToggled: root._togglePicker("nightlight")
            }

            QuickToggleTile {
                width: _toggleGrid.cellW
                active: Notifications.dnd
                activeGlyph: "󰂛"
                inactiveGlyph: "󰂚"
                title: "Do Not Disturb"
                badgeCount: Notifications.dnd ? Notifications.missedCount : 0
                onToggled: Notifications.toggleDnd()
                onBadgeActivated: MenuState.showTab(2)
            }

            QuickToggleTile {
                width: _toggleGrid.cellW
                readonly property bool _ethActive: Network.connected && Network.deviceType === "ethernet"
                available: Network.toolAvailable && !_ethActive
                active: Network.wifiEnabled
                activeGlyph: "󰤨"
                inactiveGlyph: "󰤭"
                title: "Wi-Fi"
                status: !Network.toolAvailable ? "nmcli missing"
                      : _ethActive ? "Ethernet"
                      : (Network.wifiEnabled && Network.isWifi && Network.connected ? Network.connectionName : "")
                expandable: Network.toolAvailable && Network.wifiEnabled && !_ethActive
                expanded: root._picker === "wifi"
                onToggled: Network.toggleWifi()
                onExpandToggled: root._togglePicker("wifi")
            }

            QuickToggleTile {
                width: _toggleGrid.cellW
                available: Bluetooth.available
                active: Bluetooth.enabled
                activeGlyph: "󰂯"
                inactiveGlyph: "󰂲"
                title: "Bluetooth"
                status: Bluetooth.connectedCount > 0
                    ? (Bluetooth.connectedCount === 1
                        ? Bluetooth.connectedName + (Bluetooth.connectedBattery >= 0 ? "  " + Bluetooth.connectedBattery + "%" : "")
                        : Bluetooth.connectedCount + " connected")
                    : ""
                expandable: Bluetooth.available && Bluetooth.enabled
                expanded: root._picker === "bt"
                onToggled: Bluetooth.toggle()
                onExpandToggled: root._togglePicker("bt")
            }

            // Tap cycles balanced → performance → power-saver. Keep the tile
            // visible while the first read is pending so it doesn't blink out.
            QuickToggleTile {
                width: _toggleGrid.cellW
                visible: PowerProfiles.available
                available: PowerProfiles.profile !== ""
                active: PowerProfiles.profile !== "" && PowerProfiles.profile !== "balanced"
                activeGlyph: PowerProfiles.glyph
                inactiveGlyph: PowerProfiles.glyph
                title: "Power Mode"
                status: PowerProfiles.profile !== "" ? PowerProfiles.label
                      : PowerProfiles.syncing ? "Checking..."
                      : "Unavailable"
                onToggled: PowerProfiles.cycle()
            }

            QuickToggleTile {
                // Gate on the configured command's tool (mirrors the power
                // strip), not hyprlock specifically — lockCommand is editable.
                readonly property bool lockAvailable: {
                    const cmd = Settings.lockCommand
                    if (!cmd || cmd.length === 0) return false
                    if (String(cmd[0]) === "hyprlock") return SystemTools.hasHyprlock
                    return true
                }
                width: _toggleGrid.cellW
                available: lockAvailable
                activeGlyph: "󰍁"
                inactiveGlyph: "󰍁"
                title: "Lock"
                status: SystemTools.ready && !lockAvailable ? "hyprlock missing" : ""
                onToggled: {
                    MenuState.close()
                    Quickshell.execDetached(Settings.lockCommand)
                }
            }
        }

        Item { width: 1; height: root._picker !== "" ? 8 : 0
               Behavior on height { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } } }

        CollapsibleSection {
            width: parent.width
            expanded: root._picker === "wifi"
            WifiList { width: parent.width; open: root._picker === "wifi" }
        }
        CollapsibleSection {
            width: parent.width
            expanded: root._picker === "bt"
            BluetoothList { width: parent.width; open: root._picker === "bt" }
        }
        CollapsibleSection {
            width: parent.width
            expanded: root._picker === "nightlight"
            SettingsCard {
                width: parent.width
                SliderRow {
                    glyph: "󰔄"
                    label: ShellSettings.nightLightAuto ? "Temperature  ·  auto" : "Temperature"
                    displayValue: ShellSettings.nightLightTemp + "K"
                    value: ShellSettings.nightLightTemp
                    min: 3000; max: 6500; step: 100
                    glyphColor: Theme.withAlpha(Theme.warning, ShellSettings.nightLightAuto ? 0.45 : 0.85)
                    opacity: ShellSettings.nightLightAuto ? 0.45 : 1.0
                    onChanged: (v) => { if (!ShellSettings.nightLightAuto) ShellSettings.nightLightTemp = v }
                    // Sole row of its card → round both ends so the hover fill follows
                    // the card corners instead of squaring off inside them.
                    topRadius: 10; bottomRadius: 10
                }
            }
        }

        Item { width: 1; height: _quickSliders.visible ? 8 : 0 }
        SettingsCard {
            id: _quickSliders
            visible: Audio.ready || Brightness.maxBrightness > 0

            QuickSlider {
                visible: Audio.ready
                glyph: Audio.icon
                wheelKey: "volume"
                accessibleName: "Volume"
                value: Audio.uiVolume
                valueText: Audio.label
                glyphClickable: true
                onGlyphClicked: Audio.toggleMute()
                onMoved: (v) => Audio.setVolume(v)
            }
            QuickSlider {
                visible: Brightness.toolAvailable && Brightness.maxBrightness > 0
                glyph: Brightness.icon
                wheelKey: "brightness"
                accessibleName: "Brightness"
                value: Brightness.pendingPercent / 100
                valueText: Brightness.pendingPercent + "%"
                onMoved: (v) => Brightness.setPercent(Math.round(v * 100))
            }
        }

        // Sun-path arc — appears while night light is on, otherwise costs nothing.
        Item {
            id: _sunSection
            width: parent.width
            // only while auto-following the sun; a fixed manual temp wouldn't track it
            readonly property bool _show: NightLight.toolAvailable && NightLight.enabled && ShellSettings.nightLightAuto
            // snap to 4px so rows below stay on whole physical px under fractional scaling
            height: _show ? 4 * Math.ceil((_sunCard.implicitHeight + 12) / 4) : 0
            clip: true
            Behavior on height {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }
            SunArc {
                id: _sunCard
                width: parent.width
                y: 12                       // gap sits above the card → no dead space below
                shown: _sunSection._show && MenuState.open   // no canvas/buffer while the menu's closed
                opacity: _sunSection._show ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.normal } }
            }
        }

        Item { width: 1; height: 12 }

        // 2-column tile grid — same visual vocabulary as the quick-toggle tiles
        // above: standalone cards with left accent rail + icon + label/value.
        Grid {
            id: _statGrid
            width: parent.width
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            readonly property real cellW: (width - columnSpacing) / 2

            StatTile {
                id: _cpuGauge
                active: root.active
                width: _statGrid.cellW
                glyph: "󰔏"
                label: "CPU"
                value: (SysInfo.cpuPct > 0 ? Math.round(SysInfo.cpuPct * 100) + "%" : "—") +
                       (CpuTemp.temp > 0 ? "  " + Math.round(CpuTemp.temp) + "°" : "")
                progress: SysInfo.cpuPct
                accentColor: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.accent)
                alertPulse: CpuTemp.alertPulse
            }
            StatTile {
                id: _memGauge
                active: root.active
                width: _statGrid.cellW
                glyph: "󰘚"
                label: "Memory"
                value: SysInfo.memLabel
                progress: SysInfo.memPct
            }
            StatTile {
                id: _diskGauge
                active: root.active
                width: _statGrid.cellW
                glyph: "󰋊"
                label: "Storage"
                value: SysInfo.diskPct > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
                hoverValue: SysInfo.diskLabel
                progress: SysInfo.diskPct
                accentColor: SysInfo.diskPct > 0.9 ? Theme.error : (SysInfo.diskPct > 0.75 ? Theme.warning : Theme.accent)
            }
            StatTile {
                id: _battGauge
                active: root.active
                visible: Battery.available
                width: _statGrid.cellW
                glyph: Battery.icon
                label: "Battery"
                value: Battery.label
                       + (Battery.timeLabel !== "" ? "  " + Battery.timeLabel : "")
                       + (Battery.charging && Battery.rateLabel !== "" ? "  " + Battery.rateLabel : "")
                progress: Math.min(Battery.pct / 100, 1.0)
                accentColor: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.accent)
                alertPulse: Battery.alertPulse
            }
        }

        // Arc shows fraction of the current day elapsed, not raw uptime.
        Item { width: 1; height: 8 }
        StatTile {
            id: _uptimeGauge
            active: root.active
            width: parent.width
            glyph: "󰅐"
            label: "Uptime"
            value: SysInfo.uptimeLabel
            hoverValue: SysInfo.bootTimeLabel
                        + (SysInfo.processCount > 0 ? "  ·  " + SysInfo.processCount + " procs" : "")
            progress: Math.min(SysInfo.uptimeSecs / 86400, 1.0)
        }

        Item { width: 1; height: 8 }
    }
}
