pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    // no forced canvas expansion; width follows the title text
    implicitWidth:  root.show ? textClip.width : 0
    // Full bar height so the visualizer baseline sits on the bottom line.
    implicitHeight: parent ? parent.height : ShellSettings.barHeight
    clip: true
    enabled: root.show

    readonly property bool show: ShellSettings.barShowMedia && Media.shown

    // Visualizer paints only on the active monitor.
    property var screen: null
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _visualizerActive: ShellSettings.mediaProgress
        && root.show && Media.playing && Media.cavaReady && root._onActiveBar && !MenuState.open

    readonly property real _scrollSpeed:     38    // px/sec
    readonly property int  _scrollHoldStart: 900   // short: title start already visible on entry
    readonly property int  _scrollHoldEnd:   2200  // long: user reads the end

    function _resetMarquee(): void {
        _scroll.stop()
        _trackTransition.stop()
        textClip._shown = Media.label
        trackText.x = 0
        textClip.opacity = 1.0
    }
    function _startMarquee(): void {
        if (show && _onActiveBar && textClip.needsScroll && !_trackTransition.running)
            _scroll.start()
    }

    onShowChanged: {
        if (!show) _resetMarquee()
        else       Qt.callLater(_startMarquee)
    }

    Behavior on implicitWidth {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    // always-on playing indicator; hides when canvas visualizer is active
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height: 1.5
        opacity: !root.show || (_vizLoader.item ? _vizLoader.item.visible : false) || !ShellSettings.mediaProgress ? 0.0 : Media.playing ? 0.60 : 0.28
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.18; color: Theme.accent }
            GradientStop { position: 0.82; color: Theme.accent }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }

    Loader {
        id: _vizLoader
        anchors.fill: parent
        active: root._visualizerActive
        sourceComponent: Component { MediaVisualizer { barName: root.screen ? root.screen.name : "" } }
    }

    Item {
        id: textClip
        anchors.verticalCenter: parent.verticalCenter
        readonly property int  maxW: ShellSettings.barCompact ? 120 : 160
        // Reduce-motion keeps the title elided and still, so it never scrolls.
        readonly property bool needsScroll: trackText.implicitWidth > maxW && !ShellSettings.reduceMotion
        readonly property real _overflow:   Math.max(0, trackText.implicitWidth - maxW)
        // Duration of one slide, fixed speed with a floor so tiny overflows still glide.
        readonly property int  _slideMs:    Math.max(1800, Math.round(_overflow / root._scrollSpeed * 1000))
        // Return trip: no need to read it, so faster. 65% of forward duration.
        readonly property int  _returnMs:   Math.max(1100, Math.round(_slideMs * 0.65))
        width:  Math.min(trackText.implicitWidth, maxW)
        height: trackText.implicitHeight
        clip:   true

        property string _shown: ""

        Component.onCompleted: {
            _shown = Media.label
            Qt.callLater(root._startMarquee)
        }

        Text {
            id: trackText
            text:           textClip._shown
            textFormat:     Text.PlainText
            // paused: drift toward subtext as a colour cue, not just dim
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
                // only animate paused→playing; breathing takes ownership on pause
                enabled: Media.playing && !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            // breathing: slow sway while paused; Behavior restores 0.72 when it stops
            SequentialAnimation on opacity {
                running: !Media.playing && root.show && !ShellSettings.reduceMotion && !Idle.isIdle
                    && (!root.screen || Monitors.activeName === root.screen.name)
                loops: Animation.Infinite
                NumberAnimation { to: 0.60; duration: Motion.ms(1400); easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.92; duration: Motion.ms(1400); easing.type: Easing.InOutSine }
            }
        }

        Connections {
            target: Media
            function onLabelChanged() {
                if (!root.show || ShellSettings.reduceMotion) {
                    root._resetMarquee()
                    return
                }
                _scroll.stop()
                _trackTransition.restart()
            }
        }

        Connections {
            target: ShellSettings
            function onReduceMotionChanged() {
                if (ShellSettings.reduceMotion) root._resetMarquee()
                else                            root._startMarquee()
            }
        }

        // Pause marquee while screen is idle — bar isn't visible then.
        Connections {
            target: Idle
            function onIsIdleChanged() {
                if (Idle.isIdle) _scroll.stop()
                else             root._startMarquee()
            }
        }

        // Only the active monitor's bar scrolls the title (mirrors visualizer/breathing).
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

    // root hit target so the visualizer zone is also clickable
    HoverHandler { id: _rootHover; cursorShape: Qt.PointingHandCursor }

    activeFocusOnTab: root.show
    Accessible.role: Accessible.Button
    Accessible.name: Media.title.length > 0 ? "Now playing: " + Media.title : "Media"
    Accessible.description: "Activate to toggle playback. Scroll to skip tracks."

    Keys.onSpacePressed:  event => { Media.togglePlay(); event.accepted = true }
    Keys.onReturnPressed: event => { Media.togglePlay(); event.accepted = true }
    Keys.onEnterPressed:  event => { Media.togglePlay(); event.accepted = true }
    Keys.onLeftPressed:   event => { Media.previous();   event.accepted = true }
    Keys.onRightPressed:  event => { Media.next();       event.accepted = true }

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
