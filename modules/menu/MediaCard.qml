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
    readonly property bool _stackTimeLabels: _elapsedLabel.visible && _totalLabel.visible
        && width < _controlsRow.width
            + 2 * (Math.max(_elapsedLabel.implicitWidth, _totalLabel.implicitWidth) + 24)
    readonly property int _timeRowHeight: _stackTimeLabels
        ? 4 * Math.ceil((Math.max(_elapsedLabel.implicitHeight, _totalLabel.implicitHeight) + 8) / 4) : 0

    // 4px multiple: an odd height lands the bottom border on a half physical pixel and doubles it
    height: 4 * Math.ceil(Math.max(172,
        20 + _mediaCol.implicitHeight + 18 + _controlsRow.height + 26 + root._timeRowHeight) / 4)
    radius: Theme.radiusCard
    color: Theme.menuCard
    opacity: Media.shown ? 1.0 : 0.0
    visible: opacity > 0.01

    function _motionAllowed(): bool {
        return root.visible && MenuState.homeActive
            && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    }

    function _focusPlayer(): void {
        MenuState.close()
        WindowActions.focusMediaPlayer(Media.playerName, Media.title)
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

    // fade only: a scale leg ran as a third competing animation over the card
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
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) root.settleMediaVisual()
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
            onTriggered: {
                if (!MenuState.open) return
                Media.retryArt()
                _art._curUrl = ""
                _art._apply()
            }
        }
        function _failed(img) {
            if (img !== _pendingLayer) return
            _pendingLayer = null
            const dead = _curUrl
            _curUrl = ""
            if (MenuState.open) Media.artFailed(dead)
            // the service already moved the card onto the next cover it knows about
            if (_curUrl.length > 0) return
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
            if (!root._motionAllowed()) {
                img.scale = 1.0; img.opacity = maxAlpha; outgoing.opacity = 0
                _releaseLayer(outgoing)
                return
            }
            img.scale = 1.06
            _artIn.target = img;      _artIn.restart()
            _artInScale.target = img; _artInScale.restart()
            _artOut.target = outgoing; _artOut.to = 0; _artOut.restart()
        }

        Connections { target: Media; function onStableArtUrlChanged() { _art._apply() } }
        Connections { target: Media; function onArtKeyChanged() { _art._retries = 0 } }
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

    Rectangle {
        visible: Media.metadataPrivacyProtected && Media.stableArtUrl.length === 0
        anchors {
            top: parent.top; topMargin: 16
            right: parent.right; rightMargin: 18
        }
        width: 64; height: 64
        radius: width / 2
        color: Theme.withAlpha(Theme.accent, 0.06)

        ShellText {
            anchors.centerIn: parent
            text: "󰌾"
            color: Theme.withAlpha(Theme.accent, 0.22)
            font.pixelSize: Settings.fontSize + 24
        }
    }

    // the art is the jump target and fills the card; later siblings take their own clicks
    MouseArea {
        id: _playerTarget
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root._focusPlayer()
    }

    Column {
        id: _mediaCol
        anchors {
            left: parent.left; leftMargin: 16
            right: parent.right; rightMargin: 16
            bottom: _controlsRow.top; bottomMargin: 18
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
            _shownIdentity = Media.sourceLabel
            _shownTitle = Media.displayTitle
            _shownArtist = Media.displayArtist
            opacity = 1.0
            _slide = 0
        }
        Component.onCompleted: {
            _shownIdentity = Media.sourceLabel
            _shownTitle    = Media.displayTitle
            _shownArtist   = Media.displayArtist
        }

        readonly property string trackKey: Media.sourceLabel + "\u0000"
            + Media.displayTitle + "\u0000" + Media.displayArtist
        onTrackKeyChanged: {
            if (!root._motionAllowed() || (_shownTitle === "" && _shownArtist === "")) {
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
                    _mediaCol._shownIdentity = Media.sourceLabel
                    _mediaCol._shownTitle    = Media.displayTitle
                    _mediaCol._shownArtist   = Media.displayArtist
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

    // a muted 3px rail read as a border rather than a position
    Item {
        id: _seek
        visible: Media.hasPosition
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 14

        Accessible.role: Accessible.Slider
        Accessible.name: "Playback position"
        Accessible.focusable: Media.canSeek && Media.lengthKnown
        Accessible.description: Media.formatTime(Media.positionNow) + " of "
            + (Media.lengthKnown ? Media.formatTime(Media.length)
                : Media.endless ? "live" : "unknown")

        readonly property real _ratio: Math.max(0, Math.min(1, Media.positionRatio))

        Rectangle {
            id: _seekRail
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: _seekArea.containsMouse || _seekArea.pressed ? 7 : 5
            color: Theme.controlTrackFill(Theme.accent, false,
                _seekArea.containsMouse, _seekArea.pressed)
            ColorFade on color {}
            MotionBehavior on height {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: Math.round(parent.width * _seek._ratio)
                color: Theme.controlTrackFill(Theme.accent, true,
                    _seekArea.containsMouse, _seekArea.pressed)
                ColorFade on color {}
            }
        }

        MouseArea {
            id: _seekArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: Media.canSeek && Media.lengthKnown
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            function _seekTo(x) {
                if (!enabled || width <= 0) return
                Media.seekToRatio(Math.max(0, Math.min(1, x / width)))
            }
            onPressed: (e) => _seekTo(e.x)
            onPositionChanged: (e) => { if (pressed) _seekTo(e.x) }
        }
    }

    ShellText {
        id: _elapsedLabel
        visible: Media.hasPosition
        anchors {
            left: parent.left; leftMargin: 16
            verticalCenter: root._stackTimeLabels ? undefined : _controlsRow.verticalCenter
            bottom: root._stackTimeLabels ? parent.bottom : undefined
            bottomMargin: 16
        }
        text: Media.formatTime(Media.positionNow)
        color: Theme.withAlpha(Theme.text, 0.55)
        font.pixelSize: Settings.fontMicro
    }

    ShellText {
        id: _totalLabel
        visible: Media.hasPosition
        anchors {
            right: parent.right; rightMargin: 16
            verticalCenter: root._stackTimeLabels ? undefined : _controlsRow.verticalCenter
            bottom: root._stackTimeLabels ? parent.bottom : undefined
            bottomMargin: 16
        }
        text: Media.lengthKnown ? Media.formatTime(Media.length)
            : Media.endless ? "LIVE" : "--:--"
        color: Theme.withAlpha(Theme.text, 0.45)
        font.pixelSize: Settings.fontMicro
    }

    Row {
        id: _controlsRow
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom; bottomMargin: 24 + root._timeRowHeight
        }
        spacing: 26

        MediaButton {
            glyph: "󰒮"
            accessibleName: "Previous track"
            available: Media.canGoPrevious
            onTriggered: Media.previous()
        }

        Item {
            id: _playBtn
            readonly property bool _on: Media.canTogglePlaying
            width: 46; height: 44
            anchors.verticalCenter: parent.verticalCenter
            opacity: _playBtn._on ? 1.0 : Theme.disabledOpacity
            Accessible.role: Accessible.Button
            Accessible.name: Media.playing ? "Pause" : "Play"
            Accessible.focusable: _playBtn._on
            Accessible.onPressAction: if (_playBtn._on) Media.togglePlay()
            MotionBehavior on opacity {
                NumberAnimation { duration: Motion.fast }
            }

            HoverHandler { id: _playH; enabled: _playBtn._on; cursorShape: Qt.PointingHandCursor }
            TapHandler   { id: _playT; enabled: _playBtn._on; onTapped: Media.togglePlay() }

            ShellText {
                id: _playGlyph
                anchors.centerIn: parent
                property string shown: ""
                readonly property string target: Media.playing ? "󰏤" : "󰐊"
                property bool _ready: false
                text: shown
                color: _playH.hovered || _playT.pressed
                    ? Theme.mix(Theme.accent, Theme.text, 0.35) : Theme.accent
                font.pixelSize: Settings.fontSize + 13
                ColorFade on color {}

                Component.onCompleted: { shown = target; _ready = true }
                onTargetChanged: {
                    if (!_ready || !root._motionAllowed()) { shown = target; return }
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
