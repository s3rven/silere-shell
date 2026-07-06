pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    // no forced canvas expansion; width follows the enabled content
    implicitWidth:  root.show ? _content.implicitWidth : 0
    // Full bar height so the visualizer baseline sits on the bottom line.
    implicitHeight: parent ? parent.height : ShellSettings.barHeight
    clip: true
    enabled: root.show

    readonly property bool show: ShellSettings.barShowMedia && Media.shown

    // Visualizer paints only on the active monitor.
    property var screen: null
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _visualizerActive: ShellSettings.mediaProgress
        && root.show && Media.playing && Media.cavaReady && root._onActiveBar
    readonly property bool _vizVisible: _vizLoader.item ? _vizLoader.item.visible : false
    readonly property bool _helperEnabled: ShellSettings.mediaWidgetHelper
    readonly property string _playGlyph: Media.playing ? "󰏤" : "󰐊"
    property real textBudget: -1

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

    // Optional helper: subtle activity line, upgraded to seek progress when
    // MPRIS exposes track length.
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
        sourceComponent: Component { MediaVisualizer { barName: root.screen ? root.screen.name : "" } }
    }

    Row {
        id: _content
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
                font.pixelSize: Settings.fontSize + 1
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
                ShellSettings.barCompact ? 120 : 160,
                root.textBudget > 0 ? root.textBudget : 9999
            )))
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
    }

    // root hit target so the visualizer zone is also clickable
    HoverHandler { id: _rootHover; cursorShape: Qt.PointingHandCursor }

    activeFocusOnTab: root.show
    Accessible.role: Accessible.Button
    Accessible.name: Media.label.length > 0 ? "Now playing: " + Media.label : "Media"
    Accessible.description: (Media.hasPosition
        ? Media.formatTime(Media.positionNow) + " of " + Media.formatTime(Media.length) + ". "
        : "") + "Activate to toggle playback. Scroll to skip tracks."

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
