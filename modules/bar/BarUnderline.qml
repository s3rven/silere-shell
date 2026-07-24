pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: _ul
    anchors.fill: parent

    property real floatingProgress: ShellSettings.barFloating ? 1.0 : 0.0

    // Glow hugs the edge facing the desktop. Everything inside keeps its
    // bottom-anchored layout; a bottom bar mirrors the whole item vertically,
    // which flips positions and gradient directions together in one step
    // (conditional anchor flips left elements stuck on the stale edge).
    readonly property bool atBottom: ShellSettings.barPosition === "bottom"
    readonly property real wrapRadius: (ShellSettings.barCornerStyle === "round"
        ? Math.min(ShellSettings.barRadius, _ul.height / 2, _ul.width / 2) : 0)
        * _ul.floatingProgress
    transform: Scale { origin.y: _ul.height / 2; yScale: _ul.atBottom ? -1 : 1 }

    // non-visual host for all glow state/sources/animations/previews; the strips below read its properties
    Item {
        id: _lineEffect
        anchors.fill: parent

        property real _notifGlow:   0
        readonly property bool _batteryGlowEnabled: _glowEnabled && ShellSettings.underlineBattGlow
        readonly property bool _tempGlowEnabled: _glowEnabled && ShellSettings.underlineTempGlow
        readonly property bool _networkGlowEnabled: _glowEnabled && ShellSettings.underlineNetGlow
        readonly property real _batteryGlow: _batteryGlowEnabled
            ? (Battery.critical ? 0.64 - Battery.alertPulse * 0.26
               : (Battery.low   ? 0.44 - Battery.alertPulse * 0.20 : 0))
            : 0
        property real _networkGlow: 0
        property bool _netKnown: false
        property bool _lastNetConnected: false
        readonly property real _tempGlowBase: (_tempGlowEnabled && CpuTemp.hot && !CpuTemp.critical) ? 0.32 : 0
        property real _tempPulseGlow: 0
        // Reduce-motion: hold a static elevated glow on critical instead of pulsing.
        readonly property real _tempGlow: (ShellSettings.reduceMotion && _tempGlowEnabled && CpuTemp.critical)
            ? 0.5
            : _tempGlowBase + _tempPulseGlow
        readonly property real _screenshotStrength: ShellSettings.screenshotGlowSweep ? 1.1 : 1.0
        readonly property int  _screenshotDuration: ShellSettings.screenshotGlowSweep ? 800 : 650
        readonly property real _screenshotEventGlow: (_glowEnabled && ShellSettings.underlineScreenshotGlow)
            ? _screenshotGlow * (ShellSettings.screenshotGlowSweep ? 0.24 : 0.62) * _screenshotStrength : 0
        readonly property real _primaryGlow: Math.max(_notifGlow, _batteryGlow, _networkGlowEnabled ? _networkGlow : 0, _tempGlow, _screenshotEventGlow)
        readonly property real _stackedGlow: _notifGlow + _batteryGlow + (_networkGlowEnabled ? _networkGlow : 0) + _tempGlow + _screenshotEventGlow
        readonly property real _stackBonus:  Math.min(0.12, Math.max(0, _stackedGlow - _primaryGlow) * 0.18)
        readonly property real _ceiling:     _shotActive
            ? Math.min(0.95, 0.70 + 0.10 * _screenshotStrength)
            : (((_tempGlowEnabled && CpuTemp.critical) || (_batteryGlowEnabled && Battery.critical)) ? 0.74 : 0.62)
        property real _idleFloor: (_glowEnabled && ShellSettings.underlineIdleGlow) ? 0.20 : 0
        Behavior on _idleFloor {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic }
        }
        // Event intensity follows the visible glow control. Keeping this derived avoids a hidden persisted
        // value becoming stale when settings are loaded or edited outside the UI.
        readonly property real _activeGlowStrength: Math.min(1, 0.45 + 0.4 * ShellSettings.glowStrength)
        readonly property real _scaledGlow:  (_primaryGlow + _stackBonus) * _activeGlowStrength
        readonly property real _eventGlow:   Math.max(_scaledGlow, _batteryGlow, _tempGlow)
        // soft boost while cava runs — the waveform baseline sits on the underline, so glow makes them read as one
        property real _mediaGlow: (_glowEnabled && ShellSettings.mediaProgress && Media.shown && Media.cavaReady) ? 0.18 : 0
        Behavior on _mediaGlow {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic }
        }
        readonly property real _combined:    _glowEnabled ? Math.min(_ceiling, Math.max(_idleFloor, _eventGlow, _mediaGlow)) : 0

        readonly property color _screenshotColor: Theme.text
        readonly property bool _batteryCritical: _batteryGlowEnabled && Battery.critical
        readonly property bool _tempCritical: _tempGlowEnabled && CpuTemp.critical

        readonly property color _effectColorTarget: {
            if (_tempCritical) return Theme.error
            if (_batteryCritical) return Theme.error
            if (_batteryGlowEnabled && Battery.low)       return Theme.warning
            if (_shotActive)                              return _screenshotColor
            if (Notifications.lastCritical && _notifFlash.running) return Theme.error
            if (_notifFlash.running)                      return Theme.accent
            if (_tempGlowEnabled && CpuTemp.hot)          return Theme.warning
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
        // lean toward the alerting widget's zone — bar order is user-configurable, so a hardcoded side would sweep the wrong way
        function _widgetSweep(key: string): real {
            return ShellSettings.barWidgetLocate(key).zone === "left" ? 0.32 : 0.68
        }
        // gradient peak: leans toward the widget that owns the event, centred otherwise
        readonly property real _sweepCenterTarget: {
            if (_notifFlash.running)                                         return 0.50
            if (_batteryGlowEnabled && (Battery.low || Battery.critical))    return _widgetSweep("battery")
            if (_tempGlowEnabled && (CpuTemp.hot || CpuTemp.critical))       return _widgetSweep("battery")
            if (_glowEnabled && ShellSettings.underlineScreenshotGlow
                && _shotActive)                                              return ShellSettings.screenshotGlowSweep && !ShellSettings.reduceMotion
                                                                                  ? _screenshotSweepCenter : 0.50
            if (_netLossFlash.running)                                       return _widgetSweep("network")
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
            PauseAnimation { duration: Math.max(50, _lineEffect._screenshotDuration * 0.10) }
            ParallelAnimation {
                NumberAnimation {
                    target: _lineEffect; property: "_screenshotGlow"
                    to: 0.0
                    duration: _lineEffect._screenshotDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: _lineEffect; property: "_sweepSpread"
                    to: 0.28
                    duration: Math.max(220, _lineEffect._screenshotDuration * 0.65)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: _lineEffect; property: "_bloomBoost"
                    to: 0.0
                    duration: Math.max(260, _lineEffect._screenshotDuration * 0.70)
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
                duration: Math.max(480, _lineEffect._screenshotDuration)
                easing.type: Easing.InOutCubic
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_screenshotGlow"; to: 1.0; duration: Motion.ms(90); easing.type: Easing.OutCubic }
                PauseAnimation { duration: Motion.ms(90) }
                NumberAnimation {
                    target: _lineEffect; property: "_screenshotGlow"; to: 0.0
                    duration: Math.max(300, _lineEffect._screenshotDuration - Motion.ms(180))
                    easing.type: Easing.InCubic
                }
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.10; duration: Motion.ms(180); easing.type: Easing.OutCubic }
                NumberAnimation {
                    target: _lineEffect; property: "_sweepSpread"; to: 0.045
                    duration: Math.max(300, _lineEffect._screenshotDuration - Motion.ms(180))
                    easing.type: Easing.InOutCubic
                }
            }
            SequentialAnimation {
                NumberAnimation { target: _lineEffect; property: "_bloomBoost"; to: 0.06 * _lineEffect._screenshotStrength; duration: Motion.ms(100); easing.type: Easing.OutCubic }
                NumberAnimation {
                    target: _lineEffect; property: "_bloomBoost"; to: 0.0
                    duration: Math.max(300, _lineEffect._screenshotDuration - Motion.ms(100))
                    easing.type: Easing.InCubic
                }
            }
        }

        readonly property bool _glowEnabled: ShellSettings.underlineGlow

        // seeded, not bound: an overview toggle recreates this item, and starting
        // from 0 makes the next dismissal read as an arrival and flash
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
        Component.onCompleted: {
            _prevNotifCount = Notifications.activeCount
            Qt.callLater(() => {
                _settingsReady = true
                if (_canPreview()) _previewTimer.restart()
            })
        }
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
            function onUnderlineScreenshotGlowChanged() {
                if (ShellSettings.underlineScreenshotGlow && _lineEffect._canPreview()) _screenshotPreviewTimer.restart()
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
            target: _lineEffect._networkGlowEnabled ? Network : null
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
            running:        _lineEffect._tempGlowEnabled && CpuTemp.critical && !ShellSettings.reduceMotion && !Idle.isIdle
        }
    }

    // faint base track so glow mode still shows an underline with no event active; event glow draws over it
    GlowLine {
        anchors.left:        parent.left
        anchors.right:       parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom:      parent.bottom
        visible: _lineEffect._glowEnabled && opacity > 0.001
        height: 2
        opacity: Math.min(0.58, 0.34 * ShellSettings.glowStrength)
            * (1.0 - _ul.floatingProgress)
        peak:    Theme.withAlpha(Theme.mix(Theme.subtext, _lineEffect._effectColor, 0.28), 0.72)
        edge:    Theme.withAlpha(Theme.mix(Theme.subtext, _lineEffect._effectColor, 0.18), 0.30)
        center:  0.50
        spread:  0.46
        loClamp: 0.03
        hiClamp: 0.97
    }

    // flat event glow on the screen-facing side; non-floating bars only
    GlowLine {
        anchors.left:        parent.left
        anchors.right:       parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom:      parent.bottom
        visible: _lineEffect._glowEnabled && opacity > 0.001
        height: 2
        opacity: Math.min(_lineEffect._ceiling,
            _lineEffect._combined * ShellSettings.glowStrength)
            * (1.0 - _ul.floatingProgress)
        peak:    _lineEffect._stopColor
        edge:    _lineEffect._stopColorMid
        center:  _lineEffect._sweepCenter
        spread:  _lineEffect._sweepSpread
        loClamp: 0.01
        hiClamp: 0.99
    }

    FadingRim {
        id: _floatingBaseRim
        radius: _ul.wrapRadius
        rimColor: Theme.mix(Theme.subtext, _lineEffect._effectColor, 0.18)
        visible: _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.20, 0.12 * ShellSettings.glowStrength)
            * _ul.floatingProgress
    }

    GlowLine {
        id: _floatingBaseLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        visible: _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.42, 0.24 * ShellSettings.glowStrength)
            * _ul.floatingProgress
        peak:    Theme.withAlpha(Theme.mix(Theme.subtext, _lineEffect._effectColor, 0.28), 0.64)
        edge:    Theme.withAlpha(Theme.mix(Theme.subtext, _lineEffect._effectColor, 0.18), 0.26)
        center:  0.50
        spread:  0.42
        loClamp: 0.08
        hiClamp: 0.92
    }

    // event layer over the faint floating base
    FadingRim {
        id: _floatingRim
        radius: _ul.wrapRadius
        rimColor: _lineEffect._effectColor
        visible: _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.42,
            (_lineEffect._combined * 0.34 + _lineEffect._bloomBoost * 0.16)
            * ShellSettings.glowStrength) * _ul.floatingProgress
    }

    // insets past the corner arcs and fades out at both ends, no mask/FBO needed
    GlowLine {
        id: _floatingLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        visible: _lineEffect._glowEnabled && opacity > 0.001
        opacity: Math.min(0.72,
            (_lineEffect._combined * 0.58 + _lineEffect._bloomBoost * 0.28)
            * ShellSettings.glowStrength) * _ul.floatingProgress
        peak:    _lineEffect._stopColor
        edge:    _lineEffect._stopColorMid
        center:  _lineEffect._sweepCenter
        // a wider minimum fan than the flat line keeps the floating glow soft
        spread:  Math.max(0.20, _lineEffect._sweepSpread)
        loClamp: 0.08
        hiClamp: 0.92
    }

    // six 1px gradient strips approximate a vertical halo without MultiEffect/offscreen targets;
    // spread widens per row so the bloom fans out instead of rising as a hard-edged column
    Repeater {
        model: [
            { y: 1, c: 0.34, b: 0.38, s: 1.00 },
            { y: 2, c: 0.24, b: 0.28, s: 1.16 },
            { y: 3, c: 0.16, b: 0.20, s: 1.34 },
            { y: 4, c: 0.10, b: 0.14, s: 1.54 },
            { y: 5, c: 0.06, b: 0.09, s: 1.76 },
            { y: 6, c: 0.03, b: 0.05, s: 2.00 }
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
            spread: Math.min(0.46, _lineEffect._sweepSpread * modelData.s)
        }
    }

    // localized moving streak, kept visually distinct from the centered bloom flash above
    Rectangle {
        id: _shotStreak
        readonly property real _trackW: Math.max(0, parent.width - _ul.wrapRadius * 2)
        readonly property real _streakW: Math.min(_trackW, Math.min(180, Math.max(64, _trackW * 0.16)))
        readonly property color _edgeColor: Qt.rgba(_lineEffect._screenshotColor.r,
                                                    _lineEffect._screenshotColor.g,
                                                    _lineEffect._screenshotColor.b, 0)

        x: Math.max(_ul.wrapRadius, Math.min(parent.width - _ul.wrapRadius - width,
            _ul.wrapRadius + _lineEffect._screenshotSweepCenter * _trackW - width / 2))
        anchors.bottom: parent.bottom
        width: _streakW
        height: 4
        antialiasing: false
        visible: _lineEffect._glowEnabled && ShellSettings.underlineScreenshotGlow
            && ShellSettings.screenshotGlowSweep && _lineEffect._shotActive && _trackW > 1
        opacity: Math.min(0.9,
            _lineEffect._screenshotGlow * 0.72 * _lineEffect._screenshotStrength)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: _shotStreak._edgeColor }
            GradientStop { position: 0.5; color: _lineEffect._screenshotColor }
            GradientStop { position: 1.0; color: _shotStreak._edgeColor }
        }
    }

}
