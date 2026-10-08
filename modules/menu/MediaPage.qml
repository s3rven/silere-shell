pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../config"
import "../../services"
import "../common"
import "controls"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight
    onPageHidden: root.settleVisuals()

    readonly property bool _motionOk: root.active && root.visible && MenuState.mediaActive
        && Motion.allowsMotion(Idle.isQuiet, ShellSettings.reduceMotion)
    on_MotionOkChanged: if (!root._motionOk) root.settleVisuals()
    readonly property bool _coverWanted: root.active && MenuState.mediaActive && !Idle.isQuiet
    on_CoverWantedChanged: {
        if (root._coverWanted) _cover._apply()
        else _artRetry.stop()
    }
    readonly property string _subline: [Media.displayArtist, Media.displayAlbum]
        .filter(s => s.length > 0).join(" · ")
    readonly property string _titleNow: Media.displayTitle.length > 0 ? Media.displayTitle
        : Media.displayArtist.length > 0 ? Media.displayArtist
        : Media.sourceLabel.length > 0 ? Media.sourceLabel
        : "Media"
    readonly property string _subNow: Media.displayTitle.length > 0 ? root._subline : ""
    readonly property string _trackKey: root._titleNow + "\u0000" + root._subNow
    property string _shownTitle: ""
    property string _shownSub: ""
    property real _textOpacity: 1
    property real _textSlide: 0

    on_TrackKeyChanged: {
        if (!root._motionOk || (root._shownTitle === "" && root._shownSub === "")) {
            _textSwap.stop()
            root._settleText()
            return
        }
        _textSwap.restart()
    }
    Component.onCompleted: root._settleText()

    function _settleText(): void {
        root._shownTitle = root._titleNow
        root._shownSub = root._subNow
        root._textOpacity = 1
        root._textSlide = 0
    }

    function settleVisuals(): void {
        _titleScroll.stop()
        _titleReturn.stop()
        _titleText.x = 0
        if (_fadeIn.running) _fadeIn.complete()
        _textSwap.stop()
        root._settleText()
        _playStamp.stop()
        _playGlyph.shown = _playGlyph.target
        _playGlyph.scale = 1
    }

    SequentialAnimation {
        id: _textSwap
        NumberAnimation { target: root; property: "_textOpacity"; to: 0; duration: Motion.ms(110); easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                root._shownTitle = root._titleNow
                root._shownSub = root._subNow
                root._textSlide = 6
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_textOpacity"; to: 1; duration: Motion.ms(200); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_textSlide"; to: 0; duration: Motion.ms(260); easing.type: Easing.OutCubic }
        }
    }

    function dismissInline(): bool {
        return false
    }

    function _openPlayer(): void {
        MenuState.close()
        WindowActions.focusMediaPlayer(Media.playerName, Media.title)
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root.settleVisuals()
        }
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            id: _header
            x: 4
            width: parent.width - 8
            height: Metrics.snap4Up(_heading.implicitHeight + 2 + _source.implicitHeight)

            ShellText {
                id: _heading
                anchors { top: parent.top; left: parent.left; right: _open.left; rightMargin: 12 }
                text: "Now Playing"
                color: Theme.text
                font.pixelSize: Settings.fontSize + 5
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            ShellText {
                id: _source
                anchors { top: _heading.bottom; topMargin: 2; left: parent.left; right: _open.left; rightMargin: 12 }
                text: Media.sourceLabel + (Media.playing ? "" : " · Paused")
                color: Theme.withAlpha(Theme.subtext, 0.78)
                font.pixelSize: Settings.fontLabel
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Item {
                id: _open
                readonly property bool _hot: _openHover.hovered || _openTap.pressed
                anchors { right: parent.right; verticalCenter: _source.verticalCenter }
                width: _openText.implicitWidth + 8
                height: Math.max(24, _openText.implicitHeight + 8)
                visible: Media.playerName.length > 0
                Accessible.role: Accessible.Button
                Accessible.name: "Open " + Media.sourceLabel
                Accessible.onPressAction: root._openPlayer()

                HoverHandler { id: _openHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: _openTap; onTapped: root._openPlayer() }

                ShellText {
                    id: _openText
                    anchors.centerIn: parent
                    text: "Open  󰏌"
                    color: _open._hot ? Theme.withAlpha(Theme.text, 0.92) : Theme.withAlpha(Theme.subtext, 0.82)
                    font.pixelSize: Settings.fontLabel
                    font.weight: Font.Medium
                    ColorFade on color {}
                }
            }
        }

        Item { width: 1; height: 12 }

        ClippingRectangle {
            id: _cover
            readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            readonly property int _decode: Math.ceil(width * _dpr)
            readonly property real _shown: Math.max(_artA.opacity, _artB.opacity)
            width: parent.width
            height: width
            radius: Theme.radiusCard
            color: Theme.menuControl

            property bool _useA: true
            property string _curUrl: ""
            property var _pending: null
            property int _retries: 0

            function _apply(): void {
                if (!root._coverWanted) return
                const url = Media.stableArtUrl
                if (url === _cover._curUrl) return
                if (_fadeIn.running) _fadeIn.complete()
                _cover._curUrl = url
                _cover._pending = null
                _artRetry.stop()
                if (url.length === 0) {
                    _artA.opacity = 0; _artA.source = ""
                    _artB.opacity = 0; _artB.source = ""
                    return
                }
                const idle = _cover._useA ? _artB : _artA
                _cover._pending = idle
                // re-assigning an identical source is a no-op in Qt; clear first so a retry reloads
                if (String(idle.source) === url) idle.source = ""
                idle.source = url
            }

            function _status(img, isA: bool): void {
                // object identity, not URL compare: Qt normalises URLs
                if (img !== _cover._pending) return
                if (img.status === Image.Error) {
                    _cover._pending = null
                    const dead = _cover._curUrl
                    _cover._curUrl = ""
                    if (root._coverWanted) Media.artFailed(dead)
                    if (_cover._curUrl.length > 0) return
                    if (root._coverWanted && _cover._retries < 3) { _cover._retries++; _artRetry.restart() }
                    return
                }
                if (img.status !== Image.Ready) return
                _cover._pending = null
                _cover._retries = 0
                _cover._useA = isA
                const outgoing = isA ? _artB : _artA
                img.z = 1; outgoing.z = 0
                if (!root._motionOk) {
                    img.opacity = 1
                    outgoing.opacity = 0; outgoing.source = ""
                    return
                }
                img.opacity = 0
                _fadeIn.target = img
                _fadeIn.outgoing = outgoing
                _fadeIn.restart()
            }

            Timer {
                id: _artRetry
                interval: 2500
                onTriggered: {
                    if (!root._coverWanted) return
                    Media.retryArt()
                    _cover._curUrl = ""
                    _cover._apply()
                }
            }

            Connections { target: Media; function onStableArtUrlChanged() { _cover._apply() } }
            Connections { target: Media; function onArtKeyChanged() { _cover._retries = 0 } }
            Component.onCompleted: _cover._apply()

            NumberAnimation {
                id: _fadeIn
                property var outgoing: null
                property: "opacity"
                to: 1
                duration: Motion.ms(320)
                easing.type: Easing.OutCubic
                onFinished: {
                    const old = _fadeIn.outgoing
                    _fadeIn.outgoing = null
                    if (old && old !== _fadeIn.target) { old.opacity = 0; old.source = "" }
                }
            }

            ShellText {
                anchors.centerIn: parent
                opacity: 1 - _cover._shown
                visible: opacity > 0.01
                text: Media.metadataPrivacyProtected ? "󰌾" : "󰝚"
                color: Theme.withAlpha(Theme.subtext, 0.45)
                font.pixelSize: Math.round(_cover.width * 0.22)
            }
            Image {
                id: _artA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // uncached: caching keeps every past track's decode for the whole session
                cache: false
                sourceSize.width: _cover._decode
                sourceSize.height: _cover._decode
                opacity: 0
                visible: opacity > 0.01
                onStatusChanged: _cover._status(_artA, true)
            }
            Image {
                id: _artB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: _cover._decode
                sourceSize.height: _cover._decode
                opacity: 0
                visible: opacity > 0.01
                onStatusChanged: _cover._status(_artB, false)
            }
            OutlineBorder {
                z: 2
                radius: _cover.radius
                outlineWidth: 1
                outlineColor: Theme.menuControlLine
            }
        }

        Item { width: 1; height: 14 }

        Column {
            id: _trackCol
            width: parent.width
            opacity: root._textOpacity
            transform: Translate { y: root._textSlide }

            Item {
                id: _titleClip
                x: 4
                width: parent.width - 8
                height: _titleText.implicitHeight
                clip: _titleText.x < 0 || _titleScroll.running
                readonly property real _overflow: Math.max(0, _titleText.implicitWidth - width)
                readonly property int _slideMs: Math.max(900, Math.round(_overflow / 38 * 1000))

                HoverHandler { id: _titleHover }

                ShellText {
                    id: _titleText
                    readonly property bool _unrolled: _titleScroll.running || x < 0
                    width: _unrolled ? implicitWidth : parent.width
                    text: root._shownTitle
                    color: Theme.text
                    font.pixelSize: Settings.fontSize + 4
                    font.weight: Font.DemiBold
                    elide: _unrolled ? Text.ElideNone : Text.ElideRight
                }

                SequentialAnimation {
                    id: _titleScroll
                    running: _titleHover.hovered && _titleClip._overflow > 0 && root._motionOk
                    onRunningChanged: {
                        if (running) _titleReturn.stop()
                        else if (_titleText.x < 0 && root._motionOk) _titleReturn.restart()
                        else _titleText.x = 0
                    }
                    PauseAnimation { duration: Motion.ms(450) }
                    // linear, or the declared speed never happens
                    NumberAnimation {
                        target: _titleText; property: "x"
                        to: -_titleClip._overflow; duration: _titleClip._slideMs; easing.type: Easing.Linear
                    }
                    PauseAnimation { duration: Motion.ms(1400) }
                    NumberAnimation {
                        target: _titleText; property: "x"
                        to: 0; duration: Motion.medium; easing.type: Easing.OutCubic
                    }
                }
                NumberAnimation {
                    id: _titleReturn
                    target: _titleText; property: "x"
                    to: 0; duration: Motion.fast; easing.type: Easing.OutCubic
                }
            }

            ShellText {
                x: 4
                width: parent.width - 8
                topPadding: 3
                visible: root._shownSub.length > 0
                text: root._shownSub
                color: Theme.withAlpha(Theme.subtext, 0.86)
                font.pixelSize: Settings.fontSize
                elide: Text.ElideRight
            }
        }

        Item { width: 1; height: 12 }

        Item {
            id: _seek
            visible: Media.hasPosition
            x: 4
            width: parent.width - 8
            height: 22
            readonly property real _timeW: Math.max(_elapsedLabel.implicitWidth, _totalLabel.implicitWidth)

            ShellText {
                id: _elapsedLabel
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: _seek._timeW
                text: Media.formatElapsed(_seekTrack.dragging
                    ? _seekTrack.shownValue * Media.length : Media.positionNow, Media.length)
                color: _seekTrack.dragging ? Theme.withAlpha(Theme.text, 0.85) : Theme.menuTextDetail
                font.pixelSize: Settings.fontMicro
                ColorFade on color {}
            }

            SliderTrack {
                id: _seekTrack
                anchors {
                    left: _elapsedLabel.right; leftMargin: 10
                    right: _totalLabel.left; rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                min: 0; max: 1; step: 0
                value: Media.positionRatio
                interactive: Media.canSeek && Media.lengthKnown
                showThumb: interactive
                railHeight: 4
                thumbWidth: 12; thumbHeight: 12
                wavy: true
                waveAmplitude: Media.playing ? 2.5 : 0
                waveFlowing: Media.playing && root._motionOk && !_seekTrack.dragging
                hitPad: 8
                commitOnRelease: true
                interactionKey: String(Media.trackRevision)
                accessibleName: "Playback position"
                accessibleValueText: Media.formatTime(Media.positionNow) + " of "
                    + (Media.lengthKnown ? Media.formatTime(Media.length)
                        : Media.endless ? "live" : "unknown")
                onChanged: (v) => Media.seekToRatio(v)
            }

            ShellText {
                id: _totalLabel
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: _seek._timeW
                horizontalAlignment: Text.AlignRight
                text: Media.lengthKnown ? Media.formatTime(Media.length)
                    : Media.endless ? "LIVE" : "--:--"
                color: Theme.menuTextDetail
                font.pixelSize: Settings.fontMicro
            }
        }

        Item { width: 1; height: 6; visible: _seek.visible }

        Item {
            width: parent.width
            height: 52

            Row {
                anchors.centerIn: parent
                spacing: 18

                MediaButton {
                    visible: Media.canShuffle || Media.canLoop
                    glyph: "󰒟"
                    lit: Media.shuffle
                    accessibleName: Media.shuffle ? "Shuffle on" : "Shuffle off"
                    available: Media.canShuffle
                    onTriggered: Media.toggleShuffle()
                }

                MediaButton {
                    glyph: "󰒮"
                    accessibleName: "Previous track"
                    available: Media.canGoPrevious
                    onTriggered: Media.previous()
                }

                Item {
                    id: _playBtn
                    readonly property bool _on: Media.canTogglePlaying
                    width: 52; height: 52
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
                        font.pixelSize: Settings.fontSize + 15
                        ColorFade on color {}

                        Component.onCompleted: { shown = target; _ready = true }
                        onTargetChanged: {
                            if (!_ready || !root._motionOk) { shown = target; return }
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

                MediaButton {
                    visible: Media.canShuffle || Media.canLoop
                    glyph: Media.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                    lit: Media.loopState !== MprisLoopState.None
                    accessibleName: Media.loopState === MprisLoopState.Track ? "Repeat this track"
                        : Media.loopState === MprisLoopState.Playlist ? "Repeat all" : "Repeat off"
                    available: Media.canLoop
                    onTriggered: Media.cycleLoop()
                }
            }
        }

        Column {
            width: parent.width
            visible: Media.playerCount > 1

            SectionLabel { label: "Players" }
            SettingsCard {
                dividerIndent: 42

                Repeater {
                    model: Media.playerList

                    ControlRow {
                        id: _playerRow
                        required property var modelData
                        readonly property string _name: SafeText.singleLineText(
                            modelData.identity || modelData.desktopEntry || modelData.dbusName, 128)
                        glyph: modelData.isPlaying ? "󰐊" : "󰏤"
                        title: _playerRow._name
                        status: SafeText.singleLineText(modelData.trackTitle, 128)
                        active: modelData === Media.player
                        onActivated: Media.preferredPlayer = modelData.dbusName
                    }
                }
            }
        }

        Item { width: 1; height: 8 }
    }
}
