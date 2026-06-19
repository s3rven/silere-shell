import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    implicitWidth:  root.show ? textClip.width : 0
    // Full bar height so the visualizer baseline sits on the bottom line.
    implicitHeight: parent ? parent.height : 24
    clip: true
    enabled: root.show

    readonly property bool show: Media.shown

    // Visualizer paints only on the active monitor.
    property var screen: null

    // Marquee: slide speed (px/s) and per-end hold times.
    // Start hold is short — the user already sees the title beginning during
    // the track transition. End hold is long so the full title end can be read.
    readonly property real _scrollSpeed:     38    // px/sec
    readonly property int  _scrollHoldStart: 900   // ms at x=0 (start already visible)
    readonly property int  _scrollHoldEnd:   2200  // ms at x=-overflow (user reads end)

    // Shared marquee plumbing: every state change (show/hide, label swap,
    // reduce-motion, idle) either resets to a parked title or resumes the
    // scroll if the current title still overflows.
    function _resetMarquee(): void {
        _scroll.stop()
        _trackTransition.stop()
        textClip._shown = Media.label
        trackText.x = 0
        textClip.opacity = 1.0
    }
    function _startMarquee(): void {
        if (show && textClip.needsScroll && !_trackTransition.running)
            _scroll.start()
    }

    onShowChanged: {
        if (!show) _resetMarquee()
        else       Qt.callLater(_startMarquee)
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: Motion.ms(220); easing.type: Easing.OutCubic }
    }

    // Thin accent baseline — always-on playing indicator that requires no
    // cava and no settings. Hides automatically when the full canvas
    // visualizer is active (it provides its own outline at the same position).
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height: 1.5
        // Full opacity while playing, half while paused — stays visible as long
        // as any player is connected, hides only when the media widget itself hides.
        opacity: !root.show || (_vizLoader.item ? _vizLoader.item.visible : false) || !ShellSettings.mediaProgress ? 0.0 : Media.playing ? 0.60 : 0.28
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.medium } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.18; color: Theme.accent }
            GradientStop { position: 0.82; color: Theme.accent }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }

    // Visualizer (Loader-gated): the threaded Canvas only exists when the
    // visualizer setting is on, so default users pay nothing for it.
    Loader {
        id: _vizLoader
        anchors.fill: parent
        // Avoid retaining a threaded Canvas on every monitor while media is
        // hidden. Only the active monitor paints the visualizer.
        active: ShellSettings.mediaProgress && root.show
            && (!root.screen || Monitors.activeName === root.screen.name)
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

        // Held value, swapped at opacity 0 during the crossfade.
        property string _shown: ""

        Component.onCompleted: {
            _shown = Media.label
            Qt.callLater(root._startMarquee)
        }

        Text {
            id: trackText
            text:           textClip._shown
            textFormat:     Text.PlainText
            // Paused desaturates toward subtext (a colour cue, not just dimming)
            // so a stalled title doesn't read as a styling bug.
            readonly property color _base: Media.playing ? Theme.text
                                                          : Theme.mix(Theme.text, Theme.subtext, 0.55)
            color:          _rootHover.hovered ? Theme.mix(_base, Theme.accent, 0.30) : _base
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            width: ShellSettings.reduceMotion ? textClip.maxW : implicitWidth
            elide: ShellSettings.reduceMotion ? Text.ElideRight : Text.ElideNone

            opacity: Media.playing ? 1.0 : 0.72
            Behavior on opacity { NumberAnimation { duration: Motion.medium } }

            // Paused "breathing": a slow opacity sway — a living-but-resting cue
            // that a flat dim can't give. Only while paused + visible + motion on;
            // when it stops, the binding above restores the rest value.
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

        // Stop/resume the marquee when reduce-motion is toggled at runtime.
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

        // Ping-pong marquee. Forward: OutCubic — snaps past the already-read
        // start, decelerates into the end so it's comfortable to read.
        // Return: InOutSine at 65% of forward duration — smooth, unobtrusive.
        // Asymmetric holds: short at start (title beginning is already in view),
        // long at end so the user can finish reading the title.
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

        // Crossfade on track change: fade out, swap text, fade in, then scroll.
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
            }
        }

    }

    // On the root so the whole bar-height widget (visualizer included) is the
    // hit target, not just the one-line title.
    HoverHandler { id: _rootHover; cursorShape: Qt.PointingHandCursor }

    // Left-click toggles playback; middle-click jumps to the player's window.
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
