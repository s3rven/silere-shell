pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: _ul
    anchors.fill: parent

    // Glow hugs the edge facing the desktop. Everything inside keeps its
    // bottom-anchored layout; a bottom bar mirrors the whole item vertically,
    // which flips positions and gradient directions together in one step
    // (conditional anchor flips left elements stuck on the stale edge).
    readonly property bool atBottom: ShellSettings.barPosition === "bottom"
    // no separate wrap mode for glow, both styles adapt to floating geometry
    readonly property bool wrapFloating: ShellSettings.barFloating
    // Corner curve of the floating bar: wrap borders take it as their radius,
    // flat-line glow elements inset by it (mirrors Bar.qml's _barLine inset)
    // instead of jutting straight past the curve.
    readonly property real wrapRadius: ShellSettings.barFloating && ShellSettings.barCornerStyle === "round"
        ? Math.min(ShellSettings.barRadius, _ul.height / 2, _ul.width / 2)
        : 0
    transform: Scale { origin.y: _ul.height / 2; yScale: _ul.atBottom ? -1 : 1 }

    // Non-visual host for all glow state, sources, animations and previews; the
    // strips below read its properties. (It used to also draw the flat edge line,
    // now broken out as _edgeLine.)
    Item {
        id: _lineEffect
        anchors.fill: parent

        property real _notifGlow:   0
        readonly property real _batteryGlow: (_glowEnabled && ShellSettings.underlineBattGlow)
            ? (Battery.critical ? 0.64 - Battery.alertPulse * 0.26
               : (Battery.low   ? 0.44 - Battery.alertPulse * 0.20 : 0))
            : 0
        property real _networkGlow: 0
        property bool _netKnown: false
        property bool _lastNetConnected: false
        readonly property real _tempGlowBase: (_glowEnabled && ShellSettings.underlineTempGlow && CpuTemp.hot && !CpuTemp.critical) ? 0.32 : 0
        property real _tempPulseGlow: 0
        // Reduce-motion: hold a static elevated glow on critical instead of pulsing.
        readonly property real _tempGlow: (ShellSettings.reduceMotion && ShellSettings.underlineTempGlow && _glowEnabled && CpuTemp.critical)
            ? 0.5
            : _tempGlowBase + _tempPulseGlow
        readonly property real _screenshotStrength: Math.max(0.4, Math.min(1.8, ShellSettings.screenshotGlowStrength))
        readonly property real _screenshotEventGlow: (_glowEnabled && ShellSettings.underlineScreenshotGlow)
            ? _screenshotGlow * (ShellSettings.screenshotGlowSweep ? 0.24 : 0.62) * _screenshotStrength : 0
        readonly property real _primaryGlow: Math.max(_notifGlow, _batteryGlow, _networkGlow, _tempGlow, _screenshotEventGlow)
        readonly property real _stackedGlow: _notifGlow + _batteryGlow + _networkGlow + _tempGlow + _screenshotEventGlow
        readonly property real _stackBonus:  Math.min(0.12, Math.max(0, _stackedGlow - _primaryGlow) * 0.18)
        readonly property real _ceiling:     _shotActive
            ? Math.min(0.95, 0.70 + 0.10 * _screenshotStrength)
            : ((CpuTemp.critical || Battery.critical) ? 0.74 : 0.62)
        property real _idleFloor: (_glowEnabled && ShellSettings.underlineIdleGlow) ? 0.20 : 0
        Behavior on _idleFloor {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic }
        }
        readonly property real _scaledGlow:  (_primaryGlow + _stackBonus) * ShellSettings.activeGlowStrength
        readonly property real _eventGlow:   Math.max(_scaledGlow, _batteryGlow, _tempGlow)
        // Soft boost while the cava visualizer is running — the waveform baseline
        // sits on the underline, so the glow makes them read as one element.
        property real _mediaGlow: (_glowEnabled && ShellSettings.mediaProgress && Media.shown && Media.cavaReady) ? 0.18 : 0
        Behavior on _mediaGlow {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic }
        }
        readonly property real _combined:    _glowEnabled ? Math.min(_ceiling, Math.max(_idleFloor, _eventGlow, _mediaGlow)) : 0

        readonly property color _screenshotColor: Theme.text

        readonly property color _effectColorTarget: {
            if (CpuTemp.critical)                         return Theme.error
            if (Battery.critical)                         return Theme.error
            if (Battery.low)                              return Theme.warning
            if (_shotActive)                              return _screenshotColor
            if (Notifications.lastCritical && _notifFlash.running) return Theme.error
            if (_notifFlash.running)                      return Theme.accent
            if (CpuTemp.hot)                              return Theme.warning
            return Theme.accent
        }
        property color _effectColor: _effectColorTarget
        Behavior on _effectColor { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.ms(350) } }

        property color _stopColor: Qt.rgba(
            _effectColorTarget.r, _effectColorTarget.g, _effectColorTarget.b, 0.9
        )
        Behavior on _stopColor { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.ms(350) } }
        property color _stopColorMid: Qt.rgba(
            _effectColorTarget.r, _effectColorTarget.g, _effectColorTarget.b, 0.45
        )
        Behavior on _stopColorMid { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.ms(350) } }
        property real _sweepSpread: 0.28
        property real _bloomBoost:  0.0
        property real _screenshotSweepCenter: 0.50
        // gradient peak: right-biased for right-side widgets, centred otherwise
        readonly property real _sweepCenterTarget: {
            if (_notifFlash.running)                                         return 0.50
            if (_glowEnabled && ShellSettings.underlineBattGlow
                && (Battery.low || Battery.critical))                        return 0.68
            if (_glowEnabled && ShellSettings.underlineTempGlow
                && (CpuTemp.hot || CpuTemp.critical))                        return 0.68
            if (_glowEnabled && ShellSettings.underlineScreenshotGlow
                && _shotActive)                                              return ShellSettings.screenshotGlowSweep && !ShellSettings.reduceMotion
                                                                                  ? _screenshotSweepCenter : 0.50
            if (_netLossFlash.running)                                       return 0.68
            return 0.50
        }
        property real _sweepCenter: _sweepCenterTarget
        Behavior on _sweepCenter {
            // sweep already animates this frame-by-frame, a second Behavior would lag behind it
            enabled: !ShellSettings.reduceMotion
                && !(_lineEffect._shotActive && ShellSettings.screenshotGlowSweep)
            NumberAnimation { duration: Motion.ms(400); easing.type: Easing.OutCubic }
        }

        property real _screenshotGlow: 0.0
        readonly property bool _shotActive: _screenshotGlow > 0.001

        function _playScreenshot(): void {
            _screenshotPulse.stop()
            _screenshotSweep.stop()
            _screenshotGlow = 0
            _bloomBoost = 0
            if (ShellSettings.screenshotGlowSweep && !ShellSettings.reduceMotion)
                _screenshotSweep.restart()
            else
                _screenshotPulse.restart()
        }

        Connections {
            target: Screenshot
            function onFlashed() {
                _lineEffect._skipNextNotif = true
                _skipResetTimer.restart()
                if (ShellSettings.underlineScreenshotGlow && ShellSettings.underlineGlow)
                    _lineEffect._playScreenshot()
            }
        }

        Timer {
            id: _skipResetTimer
            interval: 1000
            onTriggered: _lineEffect._skipNextNotif = false
        }

        SequentialAnimation {
            id: _screenshotPulse
            ScriptAction { script: {
                _lineEffect._screenshotSweepCenter = 0.50
                _lineEffect._sweepSpread = 0.16
                _lineEffect._bloomBoost = 0
            } }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_screenshotGlow"; to: 1.0; duration: Motion.ms(100); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.38; duration: Motion.ms(260); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost"; to: 0.30 * _lineEffect._screenshotStrength; duration: Motion.ms(120); easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: Math.max(50, ShellSettings.screenshotGlowDuration * 0.10) }
            ParallelAnimation {
                NumberAnimation {
                    target: _lineEffect; property: "_screenshotGlow"
                    to: 0.0
                    duration: ShellSettings.screenshotGlowDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: _lineEffect; property: "_sweepSpread"
                    to: 0.28
                    duration: Math.max(220, ShellSettings.screenshotGlowDuration * 0.65)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: _lineEffect; property: "_bloomBoost"
                    to: 0.0
                    duration: Math.max(260, ShellSettings.screenshotGlowDuration * 0.70)
                    easing.type: Easing.OutCubic
                }
            }
        }

        ParallelAnimation {
            id: _screenshotSweep

            ScriptAction { script: {
                _lineEffect._screenshotSweepCenter = 0.04
                _lineEffect._sweepSpread = 0.045
                _lineEffect._bloomBoost = 0
            } }

            NumberAnimation {
                target: _lineEffect; property: "_screenshotSweepCenter"
                to: 0.96
                duration: Math.max(480, ShellSettings.screenshotGlowDuration)
                easing.type: Easing.InOutCubic
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_screenshotGlow"; to: 1.0; duration: Motion.ms(90); easing.type: Easing.OutCubic }
                PauseAnimation { duration: Motion.ms(90) }
                NumberAnimation {
                    target: _lineEffect; property: "_screenshotGlow"; to: 0.0
                    duration: Math.max(300, ShellSettings.screenshotGlowDuration - Motion.ms(180))
                    easing.type: Easing.InCubic
                }
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.10; duration: Motion.ms(180); easing.type: Easing.OutCubic }
                NumberAnimation {
                    target: _lineEffect; property: "_sweepSpread"; to: 0.045
                    duration: Math.max(300, ShellSettings.screenshotGlowDuration - Motion.ms(180))
                    easing.type: Easing.InOutCubic
                }
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_bloomBoost"; to: 0.06 * _lineEffect._screenshotStrength; duration: Motion.ms(100); easing.type: Easing.OutCubic }
                NumberAnimation {
                    target: _lineEffect; property: "_bloomBoost"; to: 0.0
                    duration: Math.max(300, ShellSettings.screenshotGlowDuration - Motion.ms(100))
                    easing.type: Easing.InCubic
                }
            }
        }

        readonly property bool _glowEnabled: ShellSettings.underlineGlow

        property int  _prevNotifCount: 0
        property bool _skipNextNotif: false

        Connections {
            target: Notifications
            function onActiveCountChanged() {
                const incoming = Notifications.activeCount > _lineEffect._prevNotifCount
                if (incoming && _lineEffect._skipNextNotif) {
                    _lineEffect._skipNextNotif = false
                } else if (ShellSettings.underlineNotifGlow && ShellSettings.underlineGlow && incoming && !ShellSettings.reduceMotion) {
                    _notifFlash.restart()
                }
                _lineEffect._prevNotifCount = Notifications.activeCount
            }
        }

        SequentialAnimation {
            id: _notifFlash
            ScriptAction { script: { _lineEffect._sweepSpread = 0.02 } }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_notifGlow";   to: Notifications.lastCritical ? 0.58 : 0.40; duration: Motion.ms(120); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.34; duration: Motion.ms(380); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";  to: 0.30; duration: Motion.ms(120); easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: Motion.ms(220) }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_notifGlow";   to: 0.0;  duration: Motion.ms(1200); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.28; duration: Motion.ms(800);  easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";  to: 0.0;  duration: Motion.ms(900);  easing.type: Easing.OutCubic }
            }
        }

        // previews settings changes through the real animation path while the menu is open
        property bool _settingsReady: false
        Component.onCompleted: Qt.callLater(() => { _settingsReady = true })
        function _canPreview(): bool {
            return _settingsReady && MenuState.open && ShellSettings.underlineGlow
                && !ShellSettings.reduceMotion
        }
        function _stopTransient(): void {
            _previewTimer.stop()
            _screenshotPreviewTimer.stop()
            _screenshotPulse.stop()
            _screenshotSweep.stop()
            _notifFlash.stop()
            _netLossFlash.stop()
            _screenshotGlow = 0
            _notifGlow = 0
            _networkGlow = 0
            _bloomBoost = 0
            _sweepSpread = 0.28
            _screenshotSweepCenter = 0.50
        }
        Connections {
            target: ShellSettings
            function onUnderlineGlowChanged() {
                if (ShellSettings.underlineGlow && _lineEffect._canPreview()) _previewTimer.restart()
                else if (!ShellSettings.underlineGlow) _lineEffect._stopTransient()
            }
            function onUnderlineNotifGlowChanged() {
                if (ShellSettings.underlineNotifGlow && _lineEffect._canPreview()) _previewTimer.restart()
            }
            function onUnderlineNetGlowChanged() {
                if (ShellSettings.underlineNetGlow && _lineEffect._canPreview()) _previewTimer.restart()
            }
            function onGlowStrengthChanged() {
                if (_lineEffect._canPreview()) _previewTimer.restart()
            }
            function onActiveGlowStrengthChanged() {
                if (_lineEffect._canPreview()) _previewTimer.restart()
            }
            function onUnderlineScreenshotGlowChanged() {
                if (ShellSettings.underlineScreenshotGlow && _lineEffect._canPreview()) _screenshotPreviewTimer.restart()
            }
            function onScreenshotGlowStrengthChanged() {
                if (_lineEffect._canPreview() && ShellSettings.underlineScreenshotGlow) _screenshotPreviewTimer.restart()
            }
            function onScreenshotGlowDurationChanged() {
                if (_lineEffect._canPreview() && ShellSettings.underlineScreenshotGlow) _screenshotPreviewTimer.restart()
            }
            function onScreenshotGlowSweepChanged() {
                if (_lineEffect._canPreview() && ShellSettings.underlineScreenshotGlow) _screenshotPreviewTimer.restart()
            }
            function onReduceMotionChanged() {
                if (!ShellSettings.reduceMotion) return
                _lineEffect._stopTransient()
            }
        }
        Timer {
            id: _previewTimer
            interval: 180
            onTriggered: if (_lineEffect._canPreview()) _notifFlash.restart()
        }
        Timer {
            id: _screenshotPreviewTimer
            interval: 180
            onTriggered: if (_lineEffect._canPreview() && ShellSettings.underlineScreenshotGlow)
                _lineEffect._playScreenshot()
        }

        // transition flash only, persistent offline state lives in the network widget
        function _updateNetGlow(): void {
            const currentConnected = Network.available && Network.connected
            const disconnected = Network.available && !Network.connected

            if (!_netKnown) {
                _netKnown = true
                _lastNetConnected = currentConnected
                _networkGlow = 0
                return
            }

            if (_lastNetConnected && disconnected && ShellSettings.underlineNetGlow && ShellSettings.underlineGlow && !ShellSettings.reduceMotion) {
                _netLossFlash.restart()
            } else if (currentConnected || !Network.available) {
                _netLossFlash.stop()
                _netGlowAnim.to = 0
                _netGlowAnim.restart()
            }

            _lastNetConnected = currentConnected
        }

        Connections {
            target: Network
            function onConnectedChanged() { _lineEffect._updateNetGlow() }
            function onAvailableChanged()  { _lineEffect._updateNetGlow() }
        }

        NumberAnimation {
            id: _netGlowAnim
            target: _lineEffect; property: "_networkGlow"
            duration: Motion.medium; easing.type: Easing.OutCubic
        }

        SequentialAnimation {
            id: _netLossFlash
            ScriptAction { script: { _lineEffect._sweepSpread = 0.04 } }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_networkGlow";  to: 0.42; duration: Motion.ms(130); easing.type: Easing.OutQuad  }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread";  to: 0.34; duration: Motion.ms(500); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";   to: 0.22; duration: Motion.ms(130); easing.type: Easing.OutQuad  }
            }
            PauseAnimation  { duration: Motion.ms(220) }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_networkGlow";  to: 0.0;  duration: Motion.ms(1400); easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread";  to: 0.28; duration: Motion.ms(900);  easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";   to: 0.0;  duration: Motion.ms(1000); easing.type: Easing.OutCubic }
            }
        }

        readonly property int  _tempPulseDur: Motion.ms(700)
        readonly property real _tempPeak:     0.66
        readonly property real _tempFloor:    0.24

        PulseLoop {
            id: _tempFlash
            target:         _lineEffect
            targetProperty: "_tempPulseGlow"
            peak:           _lineEffect._tempPeak
            floor:          _lineEffect._tempFloor
            duration:       _lineEffect._tempPulseDur
            running:        (_lineEffect._glowEnabled && ShellSettings.underlineTempGlow) && CpuTemp.critical && !ShellSettings.reduceMotion && !Idle.isIdle
        }
    }

    // flat edge line on the screen-facing side; non-floating bars only
    GlowLine {
        anchors.left:        parent.left
        anchors.right:       parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom:      parent.bottom
        visible: !_ul.wrapFloating && _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(_lineEffect._ceiling, _lineEffect._combined * ShellSettings.glowStrength)
        peak:    _lineEffect._stopColor
        edge:    _lineEffect._stopColorMid
        center:  _lineEffect._sweepCenter
        spread:  _lineEffect._sweepSpread
        loClamp: 0.01
        hiClamp: 0.99
    }

    // event-only unless Always visible is enabled, matching regular glow semantics
    Rectangle {
        id: _floatingRim
        anchors.fill: parent
        radius: _ul.wrapRadius
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: _lineEffect._effectColor
        visible: _ul.wrapFloating && _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.72,
            (_lineEffect._combined * 0.62 + _lineEffect._bloomBoost * 0.30)
            * ShellSettings.glowStrength)
    }

    // insets past the corner arcs and fades out at both ends, no mask/FBO needed
    GlowLine {
        id: _floatingLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        visible: _ul.wrapFloating && _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.72,
            (_lineEffect._combined * 0.58 + _lineEffect._bloomBoost * 0.28)
            * ShellSettings.glowStrength)
        peak:    _lineEffect._stopColor
        edge:    _lineEffect._stopColorMid
        center:  _lineEffect._sweepCenter
        // a wider minimum fan than the flat line keeps the floating glow soft
        spread:  Math.max(0.20, _lineEffect._sweepSpread)
        loClamp: 0.08
        hiClamp: 0.92
    }

    // six 1px gradient strips approximate a vertical halo without MultiEffect/offscreen targets
    Repeater {
        model: [
            { y: 0, c: 0.46, b: 0.50 },
            { y: 1, c: 0.30, b: 0.34 },
            { y: 2, c: 0.20, b: 0.24 },
            { y: 3, c: 0.13, b: 0.17 },
            { y: 4, c: 0.08, b: 0.11 },
            { y: 5, c: 0.04, b: 0.07 }
        ]
        GlowLine {
            required property var modelData
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: _ul.wrapRadius
            anchors.rightMargin: _ul.wrapRadius
            anchors.bottom: parent.bottom
            anchors.bottomMargin: modelData.y
            visible: _lineEffect._glowEnabled && opacity > 0.001
            opacity: Math.min(0.84,
                (_lineEffect._combined * modelData.c + _lineEffect._bloomBoost * modelData.b)
                * ShellSettings.glowStrength)
            peak:   _lineEffect._stopColor
            edge:   _lineEffect._stopColorMid
            center: _lineEffect._sweepCenter
            spread: _lineEffect._sweepSpread
        }
    }

    // localized moving streak, kept visually distinct from the centered bloom flash above
    Rectangle {
        readonly property real _trackW: Math.max(0, parent.width - _ul.wrapRadius * 2)
        readonly property real _streakW: Math.min(180, Math.max(64, _trackW * 0.16))

        x: Math.max(_ul.wrapRadius, Math.min(parent.width - _ul.wrapRadius - width,
            _ul.wrapRadius + _lineEffect._screenshotSweepCenter * _trackW - width / 2))
        anchors.bottom: parent.bottom
        width: _streakW
        height: 4
        antialiasing: false
        visible: _lineEffect._glowEnabled && ShellSettings.underlineScreenshotGlow
            && ShellSettings.screenshotGlowSweep && _lineEffect._shotActive
        opacity: Math.min(0.9,
            _lineEffect._screenshotGlow * 0.72 * _lineEffect._screenshotStrength)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: _lineEffect._screenshotColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

}
