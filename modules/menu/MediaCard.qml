pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"
import "controls"

ClippingRectangle {
    id: root
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

    function settleMediaVisual(): void {
        _mediaCol.settleText()
        if (_artIn.running) _artIn.complete()
        if (_artInScale.running) _artInScale.complete()
        if (_artOut.running) _artOut.complete()
    }

    OutlineBorder {
        // above the album art and its scrim: both fill the card and are declared later
        z: 1
        radius: root.radius
        outlineWidth: 1
        outlineColor: Theme.menuCardBorder
    }

    // fade only: a scale leg ran as a third competing animation and resampled NativeRendering text off-pixel
    Disclosure on opacity { expanded: Media.shown; enterEasing: Easing.OutCubic }

    // on reappear, text may be stranded at opacity 0 by a crossfade interrupted while hidden
    Connections {
        target: Media
        function onShownChanged() {
            if (Media.shown) root.settleMediaVisual()
        }
    }
    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root.settleMediaVisual()
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
        color: Theme.withAlpha(root.color, 0.72)
    }

    // down to the seek row, so the title and artist are part of the jump target
    MouseArea {
        id: _playerTarget
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: _seek.top
        cursorShape: Qt.PointingHandCursor
        onClicked: root._focusPlayer()
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
        function settleText(): void {
            _textFade.stop()
            _shownIdentity = Media.identity
            _shownTitle = Media.title
            _shownArtist = Media.artist
            opacity = 1.0
            _slide = 0
        }
        Component.onCompleted: {
            _shownIdentity = Media.identity
            _shownTitle    = Media.title
            _shownArtist   = Media.artist
        }

        readonly property string trackKey: Media.identity + "\u0000" + Media.title + "\u0000" + Media.artist
        onTrackKeyChanged: {
            if (ShellSettings.reduceMotion || (_shownTitle === "" && _shownArtist === "")) {
                _mediaCol.settleText()
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

            width: parent.width
            visible: _mediaCol._shownIdentity.length > 0
            text: _mediaCol._shownIdentity.toUpperCase()
                + (_switchable ? "  󰅂" : "")
            color: _switchHover ? Theme.withAlpha(Theme.text, 0.78)
                                : Theme.withAlpha(Theme.subtext, 0.62)
            font.pixelSize: Settings.fontMicro
            font.weight: Font.Medium
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            ColorFade on color {}

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
            text:           Media.lengthKnown ? Media.formatTime(Media.length) : "LIVE"
            color:          Theme.withAlpha(Theme.text, 0.55)
            font.pixelSize: Settings.fontMicro
        }

        SliderTrack {
            id: _seekTrack
            visible: Media.lengthKnown
            anchors.left:  _elapsedLabel.right; anchors.leftMargin:  8
            anchors.right: _totalLabel.left;    anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 12

            interactive: Media.canSeek && Media.lengthKnown
            showThumb:   Media.canSeek && Media.lengthKnown
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
            available: Media.canGoPrevious
            onTriggered: Media.previous()
        }

        Item {
            id: _playBtn
            readonly property bool _on: Media.canTogglePlaying
            width: 56; height: 40
            anchors.verticalCenter: parent.verticalCenter
            opacity: _playBtn._on ? 1.0 : 0.25
            MotionBehavior on opacity {
                NumberAnimation { duration: Motion.fast }
            }

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
                    outlineWidth: 1
                    outlineColor: Theme.menuControlLine
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
                font.pixelSize: Settings.fontSize + 10
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
            available: Media.canGoNext
            onTriggered: Media.next()
        }
    }
}
