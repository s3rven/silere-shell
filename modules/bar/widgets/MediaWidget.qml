pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    property bool compact: ShellSettings.barCompact
    implicitWidth:  root.show ? _content.implicitWidth + root._pillPad * 2 : 0
    implicitHeight: parent ? parent.height : ShellSettings.barHeight
    clip: true
    enabled: root.show

    readonly property bool show: ShellSettings.barShowMedia && Media.shown

    property var screen: null
    property bool barActive: true
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _visualizerActive: ShellSettings.mediaProgress
        && ShellSettings.mediaVisualizerPosition === "media"
        && !ShellSettings.reduceMotion && !Idle.isIdle
        && root.barActive && root.show && Media.playing && Media.cavaReady && root._onActiveBar
    readonly property bool _vizVisible: _vizLoader.item ? _vizLoader.item.visible : false
    readonly property bool _helperEnabled: ShellSettings.mediaWidgetHelper
    readonly property string _playGlyph: Media.playing ? "󰏤" : "󰐊"
    property real textBudget: -1
    property bool _pauseBreathSettled: false
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    readonly property real _scrollSpeed:     38
    readonly property int  _scrollHoldStart: 900
    readonly property int  _scrollHoldEnd:   2200
    readonly property int  _scrollHoldLoop:  6000

    function _resetMarquee(): void {
        _scroll.stop()
        _trackTransition.stop()
        textClip._shown = Media.label
        trackText.x = 0
        textClip.opacity = 1.0
    }
    function _startMarquee(): void {
        if (barActive && show && Media.playing && !Idle.isIdle && _onActiveBar
            && textClip.needsScroll && !_trackTransition.running)
            _scroll.start()
    }

    onShowChanged: {
        if (!show) _resetMarquee()
        else {
            if (!Media.playing) _pauseBreathSettled = false
            Qt.callLater(_startMarquee)
        }
    }
    onBarActiveChanged: {
        if (barActive) Qt.callLater(_startMarquee)
        else           _scroll.stop()
    }

    Behavior on implicitWidth {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    Item {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height: 2
        opacity: !root.show || !root._helperEnabled || root._vizVisible ? 0.0
            : Media.hasPosition ? 0.72
            : Media.playing ? 0.54 : 0.22
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1.5
            radius: height / 2
            antialiasing: true
            opacity: Media.hasPosition ? 1.0 : 0.75
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.18; color: Theme.withAlpha(Theme.accent, Media.hasPosition ? 0.22 : 0.80) }
                GradientStop { position: 0.82; color: Theme.withAlpha(Theme.accent, Media.hasPosition ? 0.22 : 0.80) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        Rectangle {
            visible: Media.hasPosition
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width * Media.positionRatio)
            height: 1.5
            radius: height / 2
            antialiasing: true
            color: Theme.accent
            Behavior on width {
                enabled: Media.playing && !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.ms(420); easing.type: Easing.Linear }
            }
        }
    }

    Loader {
        id: _vizLoader
        anchors.fill: parent
        active: root._visualizerActive
        sourceComponent: Component {
            MediaVisualizer {
                barName: root.screen ? root.screen.name : ""
                lowPower: root.compact
            }
        }
    }

    Row {
        id: _content
        x: root._pillPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root._helperEnabled ? 5 : 0
        height: Math.max(_playIcon.implicitHeight, textClip.height)

        Item {
            id: _playIconSlot
            anchors.verticalCenter: parent.verticalCenter
            visible: root._helperEnabled
            width: root._helperEnabled ? 14 : 0
            height: 16

            Text {
                id: _playIcon
                anchors.centerIn: parent
                text: root._playGlyph
                color: Media.playing
                    ? Theme.withAlpha(Theme.accent, 0.92)
                    : Theme.withAlpha(Theme.subtext, 0.72)
                font.family: Settings.font
                font.pixelSize: Settings.iconSize + 1
                renderType: Text.NativeRendering
                scale: Media.playing ? 1.0 : 0.92
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            }
        }

        Item {
            id: textClip
            anchors.verticalCenter: parent.verticalCenter
            readonly property int  maxW: Math.round(Math.max(52, Math.min(
                root.compact ? 120 : 160,
                root.textBudget > 0 ? root.textBudget : 9999
            )))
            readonly property bool needsScroll: trackText.implicitWidth > maxW && !ShellSettings.reduceMotion
            readonly property real _overflow:   Math.max(0, trackText.implicitWidth - maxW)
            readonly property int  _slideMs:    Math.max(1800, Math.round(_overflow / root._scrollSpeed * 1000))
            readonly property int  _returnMs:   Math.max(1100, Math.round(_slideMs * 0.65))
            width:  Math.min(trackText.implicitWidth, maxW)
            height: trackText.implicitHeight
            clip:   true

            property string _shown: ""
            onMaxWChanged: {
                _scroll.stop()
                trackText.x = 0
                if (needsScroll) Qt.callLater(root._startMarquee)
            }

            Component.onCompleted: {
                _shown = Media.label
                Qt.callLater(root._startMarquee)
            }

            Text {
                id: trackText
                text:           textClip._shown
                textFormat:     Text.PlainText
                readonly property color _base: Media.playing ? Theme.text
                                                              : Theme.mix(Theme.text, Theme.subtext, 0.55)
                color:          (_rootHover.hovered && ShellSettings.barHoverHighlight) ? Theme.mix(_base, Theme.accent, 0.30) : _base
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                font.family:    Settings.font
                font.pixelSize: Settings.fontSize
                renderType:     Text.NativeRendering
                width: ShellSettings.reduceMotion ? textClip.maxW : implicitWidth
                elide: ShellSettings.reduceMotion ? Text.ElideRight : Text.ElideNone

                opacity: Media.playing ? 1.0 : 0.72
                Behavior on opacity {
                    enabled: Media.playing && !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }

                SequentialAnimation on opacity {
                    running: root.barActive && !Media.playing && root.show
                        && !root._pauseBreathSettled
                        && !ShellSettings.reduceMotion && !Idle.isIdle
                        && (!root.screen || Monitors.activeName === root.screen.name)
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.60; duration: Motion.ms(1400); easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.92; duration: Motion.ms(1400); easing.type: Easing.InOutSine }
                }
            }

            Connections {
                target: Media
                function onLabelChanged() {
                    root._pauseBreathSettled = false
                    if (!root.show || ShellSettings.reduceMotion) {
                        root._resetMarquee()
                        return
                    }
                    _scroll.stop()
                    _trackTransition.restart()
                }
                function onPlayingChanged() {
                    if (Media.playing) {
                        root._startMarquee()
                    } else {
                        root._pauseBreathSettled = false
                        _scroll.stop()
                        trackText.x = 0
                    }
                }
            }

            Connections {
                target: ShellSettings
                function onReduceMotionChanged() {
                    if (ShellSettings.reduceMotion) root._resetMarquee()
                    else                            root._startMarquee()
                }
            }

            Connections {
                target: Idle
                function onIsIdleChanged() {
                    if (Idle.isIdle) _scroll.stop()
                    else             root._startMarquee()
                }
            }

            Connections {
                target: Monitors
                function onActiveNameChanged() {
                    if (root._onActiveBar) root._startMarquee()
                    else { _scroll.stop(); trackText.x = 0 }
                }
            }

            SequentialAnimation {
                id: _scroll
                loops: Animation.Infinite
                PauseAnimation  { duration: root._scrollHoldStart }
                NumberAnimation {
                    target: trackText; property: "x"
                    from: 0; to: -textClip._overflow
                    duration: textClip._slideMs; easing.type: Easing.OutCubic
                }
                PauseAnimation  { duration: root._scrollHoldEnd }
                NumberAnimation {
                    target: trackText; property: "x"
                    to: 0
                    duration: textClip._returnMs; easing.type: Easing.InOutSine
                }
                PauseAnimation { duration: root._scrollHoldLoop }
            }

            SequentialAnimation {
                id: _trackTransition
                NumberAnimation { target: textClip; property: "opacity"; to: 0;   duration: Motion.ms(100); easing.type: Easing.InCubic  }
                ScriptAction    { script: { textClip._shown = Media.label; trackText.x = 0 } }
                NumberAnimation { target: textClip; property: "opacity"; to: 1.0; duration: Motion.ms(150); easing.type: Easing.OutCubic }
                onFinished: root._startMarquee()
            }

            onNeedsScrollChanged: {
                if (!needsScroll) {
                    _scroll.stop()
                    trackText.x = 0
                } else if (!_scroll.running) {
                    root._startMarquee()
                }
            }

        }
    }

    Timer {
        interval: 15000
        running: root.barActive && root.show && !Media.playing
            && !root._pauseBreathSettled && !Idle.isIdle
        onTriggered: root._pauseBreathSettled = true
    }

    HoverHandler { id: _rootHover; cursorShape: Qt.PointingHandCursor }

    activeFocusOnTab: root.show
    Accessible.role: Accessible.Button
    Accessible.name: Media.label.length > 0 ? "Now playing: " + Media.label : "Media"
    Accessible.description: (Media.hasPosition
        ? Media.formatTime(Media.positionNow) + " of " + Media.formatTime(Media.length) + ". "
        : "") + "Activate to toggle playback. Scroll to skip tracks."
    Accessible.onPressAction: Media.togglePlay()

    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) Media.togglePlay(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) Media.togglePlay(); event.accepted = true }
    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) Media.togglePlay(); event.accepted = true }
    Keys.onLeftPressed:   event => { if (!event.isAutoRepeat) Media.previous();   event.accepted = true }
    Keys.onRightPressed:  event => { if (!event.isAutoRepeat) Media.next();       event.accepted = true }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.MiddleButton)
                HyprActions.focusMediaPlayer(Media.playerName, Media.title)
            else
                Media.togglePlay()
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, "media")
            if (n > 0)      Media.next()
            else if (n < 0) Media.previous()
        }
    }
}
