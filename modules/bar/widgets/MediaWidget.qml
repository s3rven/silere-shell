pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property bool compact: ShellSettings.barCompact
    implicitWidth:  root.show ? _content.implicitWidth + root._pillPad * 2 : 0
    implicitHeight: parent ? parent.height : ShellSettings.barHeight
    clip: true
    enabled: root.show

    readonly property bool show: ShellSettings.barShowMedia && Media.shown
    readonly property bool layoutVisible: show || implicitWidth > 0.5

    property var screen: null
    property bool barActive: true
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _visualizerActive: ShellSettings.mediaProgress
        && ShellSettings.mediaVisualizerPosition === "media"
        && !ShellSettings.reduceMotion && !Idle.isIdle
        && root.barActive && root.show && Media.playing && Media.cavaReady && root._onActiveBar
    readonly property bool _vizVisible: _visualizerActive
    readonly property bool _helperEnabled: ShellSettings.mediaWidgetHelper
    readonly property string _playGlyph: Media.playing ? "󰏤" : "󰐊"
    property real textBudget: -1
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    readonly property real _scrollSpeed:     38
    readonly property int  _scrollHoldStart: 900
    readonly property int  _scrollHoldEnd:   2200
    readonly property int  _scrollHoldLoop:  6000

    // one condition rather than a web of handlers: every transition that can strand the
    // marquee mid-slide (idle, monitor switch, sleeping bar, reduce-motion) flows through it
    readonly property bool _animatable: root.barActive && root.show
        && !ShellSettings.reduceMotion && !Idle.isIdle && root._onActiveBar

    on_AnimatableChanged: {
        if (root._animatable) return
        _trackTransition.stop()
        textClip._shown = Media.label
        textClip.opacity = 1.0
    }

    MotionBehavior on implicitWidth {
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
        MotionBehavior on opacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1.5
            radius: height / 2
            antialiasing: true
            opacity: Media.hasPosition ? 1.0 : 0.75
            color: Theme.withAlpha(Theme.accent,
                Media.hasPosition ? 0.22 : 0.80)
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
        }
    }

    Loader {
        id: _vizLoader
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        // snapped to an 8px grid: the Canvas backing this width drops and reallocates its texture on
        // every resize, and parent.width tracks root.implicitWidth's own MotionBehavior every frame
        width: 8 * Math.round(parent.width / 8)
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

            ShellText {
                id: _playIcon
                anchors.centerIn: parent
                text: root._playGlyph
                color: Media.playing
                    ? Theme.withAlpha(Theme.accent, 0.92)
                    : Theme.withAlpha(Theme.subtext, 0.72)
                font.pixelSize: Settings.iconSize + 1
                scale: Media.playing ? 1.0 : 0.92
                ColorFade on color {}
                MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
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
            // a running NumberAnimation ignores a changed to:, and the running binding below
            // can't see the distance move — restart by hand so a font or budget change re-aims it
            on_OverflowChanged: {
                trackText.x = 0
                if (_scroll.running) _scroll.restart()
            }

            Component.onCompleted: _shown = Media.label

            ShellText {
                id: trackText
                text:           textClip._shown
                readonly property color _base: Media.playing ? Theme.text
                                                              : Theme.mix(Theme.text, Theme.subtext, 0.55)
                color:          ((_rootHover.hovered && ShellSettings.barHoverHighlight) || root.activeFocus) ? Theme.mix(_base, Theme.accent, 0.30) : _base
                ColorFade on color {}
                font.pixelSize: Settings.fontSize
                width: ShellSettings.reduceMotion ? textClip.maxW : implicitWidth
                elide: ShellSettings.reduceMotion ? Text.ElideRight : Text.ElideNone

                opacity: Media.playing ? 1.0 : 0.72
                MotionBehavior on opacity {
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }
            }

            Connections {
                target: Media
                function onLabelChanged() {
                    if (root._animatable) _trackTransition.restart()
                    else                  textClip._shown = Media.label
                }
            }

            SequentialAnimation {
                id: _scroll
                running: root._animatable && Media.playing
                    && textClip.needsScroll && !_trackTransition.running
                // hover to read: the slide would otherwise walk out from under the pointer
                paused: _scroll.running && _rootHover.hovered
                onRunningChanged: if (!running) trackText.x = 0
                loops: Animation.Infinite
                PauseAnimation  { duration: root._scrollHoldStart }
                // linear, or _scrollSpeed is a lie: an eased slide covers half the distance
                // in the first fifth of _slideMs and then crawls, which is unreadable
                NumberAnimation {
                    target: trackText; property: "x"
                    from: 0; to: -textClip._overflow
                    duration: textClip._slideMs; easing.type: Easing.Linear
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
            }
        }
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
