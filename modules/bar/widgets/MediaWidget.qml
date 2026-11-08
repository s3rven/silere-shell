pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property bool compact: ShellSettings.barCompact
    implicitWidth: root.show ? Math.min(_content.implicitWidth + root._pillPad * 2,
        root.layoutWidthLimit >= 0 ? root.layoutWidthLimit : Infinity) : 0
    implicitHeight: parent ? parent.height : Metrics.barHeight
    clip: true
    enabled: root.show

    readonly property bool show: ShellSettings.barShowMedia && Media.shown
    readonly property bool layoutVisible: show || implicitWidth > 0.5

    property var screen: null
    property bool barActive: true
    readonly property bool _canInteract: root.enabled && root.visible && root.show && root.barActive && !Idle.isIdle
    readonly property bool _onActiveBar: Monitors.isActive(root.screen)
    readonly property bool _visualizerActive: ShellSettings.mediaProgress
        && ShellSettings.mediaVisualizerPosition === "media"
        && !ShellSettings.reduceMotion && !Idle.isQuiet
        && root.visible && root.barActive && root.show && Media.playing && Media.cavaReady && root._onActiveBar
    readonly property bool _vizVisible: _visualizerActive
    readonly property bool _helperEnabled: ShellSettings.mediaWidgetHelper
    readonly property string _playGlyph: Media.playing ? "󰏤" : "󰐊"
    property real textBudget: -1
    property real layoutWidthLimit: -1
    readonly property int _helperWidth: Metrics.iconCellFor(Settings.iconSize + 1)
    readonly property int _helperGap: Metrics.pillGapFor(root.compact)
    readonly property real _contentOverhead: root._pillPad * 2
        + (root._helperEnabled ? root._helperWidth + root._helperGap : 0)
    readonly property real preferredWidth: root.show
        ? Math.ceil(Math.min(trackText.implicitWidth, textClip.preferredMaxW)) + root._contentOverhead : 0
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    readonly property real _scrollSpeed:     38
    readonly property int  _scrollHoldStart: 900
    readonly property int  _scrollHoldEnd:   2200
    readonly property int  _scrollHoldLoop:  6000

    // one condition rather than a web of handlers: every transition that can strand the
    // marquee mid-slide (idle, monitor switch, sleeping bar, reduce-motion) flows through it
    readonly property bool _animatable: root.visible && root.barActive && root.show
        && !ShellSettings.reduceMotion && !Idle.isQuiet && root._onActiveBar

    on_AnimatableChanged: {
        if (root._animatable) return
        _trackTransition.stop()
        textClip._shown = Media.label
        textClip.opacity = 1.0
    }

    MotionBehavior on implicitWidth {
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    // the clock's hover cap: every other clickable bar widget shows one, so a bare title read as a label
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Metrics.barRowHeight
        radius: Metrics.hoverRadiusFor(height)
        color: _tap.pressed ? Theme.barPressed : Theme.barHover
        opacity: root._canInteract && (_tap.pressed || (_rootHover.hovered && ShellSettings.barHoverHighlight)) ? 1 : 0
        visible: opacity > 0.001
        MotionBehavior on opacity {
            gate: root._animatable
            NumberAnimation { duration: Motion.fast }
        }
        ColorFade on color { gate: root._animatable }
    }

    Item {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height: 2
        opacity: !root.show || !root._helperEnabled || root._vizVisible ? 0.0
            : Media.lengthKnown ? 0.72
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
            opacity: Media.lengthKnown ? 1.0 : 0.75
            color: Theme.withAlpha(Theme.barAccent,
                Media.lengthKnown ? 0.22 : 0.80)
        }

        Rectangle {
            visible: Media.lengthKnown
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // whole px: a sub-pixel step every position tick would repaint the bar for nothing
            width: Math.round(Math.max(0, parent.width * Media.positionRatio))
            height: 1.5
            radius: height / 2
            antialiasing: true
            color: Theme.barAccent
        }
    }

    Loader {
        id: _vizLoader
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.visualizerLiftFor(QsWindow.window ? QsWindow.window.devicePixelRatio : 1)
        anchors.horizontalCenter: parent.horizontalCenter
        // snapped to an 8px grid: the Canvas backing this width drops and reallocates its texture on
        // every resize, and parent.width tracks root.implicitWidth's own MotionBehavior every frame
        width: 8 * Math.round(parent.width / 8)
        // unloading in the same frame the opacity drops leaves the fade animating an empty Loader
        readonly property bool _wanted: root._visualizerActive
        active: _wanted || _vizHold.running
        on_WantedChanged: if (_wanted) _vizHold.stop(); else _vizHold.restart()
        Timer { id: _vizHold; interval: Motion.fast + 60 }
        opacity: _wanted ? 1.0 : 0.0
        visible: opacity > 0.001
        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
        sourceComponent: Component {
            MediaVisualizer {
                screen: root.screen
                holdFrame: true
                lowPower: root.compact
            }
        }
    }

    Row {
        id: _content
        x: root._pillPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root._helperEnabled ? root._helperGap : 0
        height: Math.max(_playIcon.implicitHeight, textClip.height)

        Item {
            id: _playIconSlot
            anchors.verticalCenter: parent.verticalCenter
            visible: root._helperEnabled
            width: root._helperEnabled ? root._helperWidth : 0
            height: _playIcon.implicitHeight

            ShellText {
                id: _playIcon
                anchors.centerIn: parent
                text: root._playGlyph
                color: Media.playing
                    ? Theme.withAlpha(Theme.barAccent, 0.92)
                    : Theme.withAlpha(Theme.barSubtext, 0.72)
                font.pixelSize: Settings.iconSize + 1
                scale: _tap.pressed ? 0.84 : Media.playing ? 1.0 : 0.92
                ColorFade on color {}
                MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            }
        }

        Item {
            id: textClip
            anchors.verticalCenter: parent.verticalCenter
            readonly property int preferredMaxW: Math.round(Math.max(52, Math.min(
                Metrics.mediaTrackWidthFor(root.compact),
                root.textBudget > 0 ? root.textBudget : 9999
            )))
            readonly property real maxW: Math.min(preferredMaxW, root.layoutWidthLimit >= 0
                ? Math.max(0, root.layoutWidthLimit - root._contentOverhead) : Infinity)
            readonly property bool needsScroll:
                maxW > 0 && trackText.implicitWidth > maxW && !ShellSettings.reduceMotion
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
                readonly property color _base: Media.playing ? Theme.barText
                                                              : Theme.mix(Theme.barText, Theme.barSubtext, 0.55)
                color:          ((_rootHover.hovered && ShellSettings.barHoverHighlight)) ? Theme.mix(_base, Theme.barAccent, 0.30) : _base
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
                // two passes per title, then rest: any running animation redraws every window each frame
                loops: 2
                PauseAnimation  { duration: root._scrollHoldStart }
                // linear, or _scrollSpeed is a lie: an eased slide covers half the distance in the first fifth of _slideMs and then crawls, which is unreadable
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

    Accessible.role: Accessible.Button
    readonly property string _playAction: !Media.canTogglePlaying ? ""
        : Media.playing ? "Pause" : "Play"
    Accessible.name: [root._playAction, Media.label].filter(part => part.length > 0).join(" ") || "Media"
    Accessible.focusable: root._canInteract
    Accessible.onPressAction: if (root._canInteract) Media.togglePlay()
    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

    HoverHandler {
        id: _rootHover
        enabled: root._canInteract
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: _tap
        enabled: root._canInteract
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (!root._canInteract) return
            if (button === Qt.MiddleButton)
                Media.focusPlayer()
            else if (button === Qt.RightButton)
                MenuState.toggleMediaAt(root, root.screen)
            else
                Media.togglePlay()
        }
    }

    WheelHandler {
        enabled: root._canInteract
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (!root._canInteract) { event.accepted = false; return }
            event.accepted = true
            const n = Scroll.processControlWheel(event, "media")
            if (n > 0)      Media.next()
            else if (n < 0) Media.previous()
        }
    }
}
