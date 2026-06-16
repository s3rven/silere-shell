import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: _ul
    anchors.fill: parent

    // Glow hugs the edge facing the desktop. Everything inside keeps its
    // bottom-anchored layout; a bottom bar mirrors the whole item vertically,
    // which flips positions and gradient directions together in one step
    // (conditional anchor flips left elements stuck on the stale edge).
    readonly property bool atBottom: ShellSettings.barPosition === "bottom"
    readonly property bool wrapFloating: ShellSettings.barFloating && ShellSettings.underlineFloatingWrap
    // Corner curve of the floating bar: wrap borders take it as their radius,
    // flat-line glow elements inset by it (mirrors Bar.qml's _barLine inset)
    // instead of jutting straight past the curve.
    readonly property real wrapRadius: ShellSettings.barFloating && ShellSettings.barCornerStyle === "round"
        ? Math.min(ShellSettings.barRadius, _ul.height / 2, _ul.width / 2)
        : 0
    transform: Scale { origin.y: _ul.height / 2; yScale: _ul.atBottom ? -1 : 1 }

    Rectangle {
        id: _lineEffect

        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        height: 1
        antialiasing: false
        visible: !_ul.wrapFloating && _glowEnabled && opacity > 0.001
        opacity: Math.min(_ceiling, _combined * ShellSettings.glowStrength)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: Math.max(0.01, _lineEffect._sweepCenter - _lineEffect._sweepSpread); color: _lineEffect._stopColorMid }
            GradientStop { position: _lineEffect._sweepCenter; color: _lineEffect._stopColor }
            GradientStop { position: Math.min(0.99, _lineEffect._sweepCenter + _lineEffect._sweepSpread); color: _lineEffect._stopColorMid }
            GradientStop { position: 1.0; color: "transparent" }
        }

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
            ? _screenshotGlow * 0.62 * _screenshotStrength : 0
        readonly property real _primaryGlow: Math.max(_notifGlow, _batteryGlow, _networkGlow, _tempGlow, _screenshotEventGlow)
        readonly property real _stackedGlow: _notifGlow + _batteryGlow + _networkGlow + _tempGlow + _screenshotEventGlow
        readonly property real _stackBonus:  Math.min(0.12, Math.max(0, _stackedGlow - _primaryGlow) * 0.18)
        readonly property real _ceiling:     _shotActive
            ? Math.min(0.95, 0.70 + 0.10 * _screenshotStrength)
            : ((CpuTemp.critical || Battery.critical) ? 0.74 : 0.62)
        readonly property real _idleFloor:   (_glowEnabled && ShellSettings.underlineIdleGlow) ? 0.20 : 0
        readonly property real _scaledGlow:  (_primaryGlow + _stackBonus) * ShellSettings.activeGlowStrength
        readonly property real _eventGlow:   Math.max(_scaledGlow, _batteryGlow, _tempGlow)
        // Soft boost while the cava visualizer is running — the waveform baseline
        // sits on the underline, so the glow makes them read as one element.
        readonly property real _mediaGlow:   (_glowEnabled && ShellSettings.mediaProgress && Media.shown && Media.cavaReady) ? 0.18 : 0
        readonly property real _combined:    _glowEnabled ? Math.min(_ceiling, Math.max(_idleFloor, _eventGlow, _mediaGlow)) : 0

        readonly property color _screenshotColor: Theme.text

        property color _effectColor: {
            if (CpuTemp.critical)                         return Theme.error
            if (Battery.critical)                         return Theme.error
            if (Battery.low)                              return Theme.warning
            if (_shotActive)                              return _screenshotColor
            if (Notifications.lastCritical && _notifFlash.running) return Theme.error
            if (_notifFlash.running)                      return Theme.accent
            if (CpuTemp.hot)                              return Theme.warning
            return Theme.accent
        }
        Behavior on _effectColor { ColorAnimation { duration: Motion.ms(350) } }

        readonly property color _stopColor: Qt.rgba(
            _effectColor.r, _effectColor.g, _effectColor.b, 0.9
        )
        readonly property color _stopColorMid: Qt.rgba(
            _effectColor.r, _effectColor.g, _effectColor.b, 0.45
        )
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
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.ms(400); easing.type: Easing.OutCubic }
        }

        property real _screenshotGlow: 0.0
        readonly property bool _shotActive: _screenshotGlow > 0.001

        Connections {
            target: Screenshot
            function onFlashed() {
                _lineEffect._skipNextNotif = true
                _skipResetTimer.restart()
                if (ShellSettings.underlineScreenshotGlow && ShellSettings.underlineGlow)
                    _screenshotFlash.restart()
            }
        }

        Timer {
            id: _skipResetTimer
            interval: 1000
            onTriggered: _lineEffect._skipNextNotif = false
        }

        SequentialAnimation {
            id: _screenshotFlash
            ScriptAction { script: {
                const sweep = ShellSettings.screenshotGlowSweep && !ShellSettings.reduceMotion
                _lineEffect._screenshotSweepCenter = sweep ? 0.18 : 0.50
                _lineEffect._sweepSpread = sweep ? 0.08 : 0.22
                _lineEffect._bloomBoost = 0.30 * _lineEffect._screenshotStrength
            } }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_screenshotGlow"; to: 1.0; duration: 45; easing.type: Easing.OutQuad }
                NumberAnimation {
                    target: _lineEffect; property: "_sweepSpread"
                    to: ShellSettings.screenshotGlowSweep && !ShellSettings.reduceMotion ? 0.36 : 0.30
                    duration: Math.max(150, ShellSettings.screenshotGlowDuration * 0.35)
                    easing.type: Easing.OutCubic
                }
            }
            PauseAnimation { duration: Math.max(30, ShellSettings.screenshotGlowDuration * 0.12) }
            ParallelAnimation {
                NumberAnimation {
                    target: _lineEffect; property: "_screenshotSweepCenter"
                    to: 0.82
                    duration: Math.max(180, ShellSettings.screenshotGlowDuration * 0.65)
                    easing.type: Easing.OutCubic
                }
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
                NumberAnimation { target: _lineEffect; property: "_notifGlow";   to: Notifications.lastCritical ? 0.58 : 0.40; duration: 90;  easing.type: Easing.OutQuad  }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.34; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";  to: 0.30; duration: 90;  easing.type: Easing.OutQuad  }
            }
            PauseAnimation { duration: 220 }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_notifGlow";   to: 0.0;  duration: 1200; easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread"; to: 0.28; duration: 800;  easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";  to: 0.0;  duration: 900;  easing.type: Easing.OutCubic }
            }
        }

        // Fires a preview notif flash after the user adjusts event strength, so
        // the effect is immediately visible without waiting for a real event.
        property bool _settingsReady: false
        Component.onCompleted: Qt.callLater(() => { _settingsReady = true })
        Connections {
            target: ShellSettings
            function onActiveGlowStrengthChanged() {
                if (_lineEffect._settingsReady && !ShellSettings.reduceMotion) _previewTimer.restart()
            }
            function onScreenshotGlowStrengthChanged() {
                if (_lineEffect._settingsReady && ShellSettings.underlineScreenshotGlow && ShellSettings.underlineGlow) _screenshotFlash.restart()
            }
            function onScreenshotGlowDurationChanged() {
                if (_lineEffect._settingsReady && ShellSettings.underlineScreenshotGlow && ShellSettings.underlineGlow) _screenshotFlash.restart()
            }
            function onScreenshotGlowSweepChanged() {
                if (_lineEffect._settingsReady && ShellSettings.underlineScreenshotGlow && ShellSettings.underlineGlow) _screenshotFlash.restart()
            }
            function onReduceMotionChanged() {
                if (!ShellSettings.reduceMotion) return
                _screenshotFlash.stop()
                _notifFlash.stop()
                _netLossFlash.stop()
                _lineEffect._screenshotGlow = 0
                _lineEffect._notifGlow = 0
                _lineEffect._networkGlow = 0
                _lineEffect._bloomBoost = 0
                _lineEffect._sweepSpread = 0.28
                _lineEffect._screenshotSweepCenter = 0.50
                _lineEffect._sweepCenter = _lineEffect._sweepCenterTarget
            }
        }
        Timer {
            id: _previewTimer
            interval: 300
            onTriggered: if (!ShellSettings.reduceMotion) _notifFlash.restart()
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
                NumberAnimation { target: _lineEffect; property: "_networkGlow";  to: 0.42; duration: 130;  easing.type: Easing.OutQuad  }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread";  to: 0.34; duration: 500;  easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";   to: 0.22; duration: 130;  easing.type: Easing.OutQuad  }
            }
            PauseAnimation  { duration: 220 }
            ParallelAnimation {
                NumberAnimation { target: _lineEffect; property: "_networkGlow";  to: 0.0;  duration: 1400; easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_sweepSpread";  to: 0.28; duration: 900;  easing.type: Easing.OutCubic }
                NumberAnimation { target: _lineEffect; property: "_bloomBoost";   to: 0.0;  duration: 1000; easing.type: Easing.OutCubic }
            }
        }

        readonly property int  _tempPulseDur: 700
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

    // Wrap borders: two concentric rims tracing the floating bar's full rounded
    // outline (brighter outer + soft inset echo). The local "bottom" is always
    // the desktop edge because the whole item flips for a bottom bar. Model is
    // static literals only — keeping wrapRadius out of it avoids delegate churn
    // while the bar width animates; the radius insets per band in the delegate.
    // Suffixes: N = normal, S = while a screenshot flash is active.
    Repeater {
        model: [
            { inset: 0, capN: 0.8,  capS: 0.46, cN: 0.65, cS: 0.40, bN: 0.40, bS: 0.10 },
            { inset: 2, capN: 0.45, capS: 0.22, cN: 0.28, cS: 0.16, bN: 0.25, bS: 0.06 }
        ]
        Rectangle {
            required property var modelData
            anchors.fill: parent
            anchors.margins: modelData.inset
            radius: Math.max(0, _ul.wrapRadius - modelData.inset)
            antialiasing: true
            color: "transparent"
            border.width: 1
            border.color: _lineEffect._effectColor
            visible: _ul.wrapFloating && _lineEffect._glowEnabled && opacity > 0.001
            opacity: {
                const shot = _lineEffect._shotActive
                return Math.min(shot ? modelData.capS : modelData.capN,
                    (_lineEffect._combined  * (shot ? modelData.cS : modelData.cN)
                     + _lineEffect._bloomBoost * (shot ? modelData.bS : modelData.bN)) * ShellSettings.glowStrength)
            }
        }
    }

    Repeater {
        model: [
            { h: 18, c: 0.07, b: 0.12, cap: 1.0  },
            { h: 12, c: 0.15, b: 0.25, cap: 1.0  },
            { h: 4,  c: 0.50, b: 0.55, cap: 0.85 }
        ]
        Rectangle {
            required property var modelData
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.leftMargin:  _ul.wrapRadius
            anchors.rightMargin: _ul.wrapRadius
            anchors.bottom: parent.bottom
            height: modelData.h
            antialiasing: false
            visible: !_ul.wrapFloating && _lineEffect._glowEnabled && opacity > 0.001
            opacity: Math.min(modelData.cap,
                (_lineEffect._combined * modelData.c + _lineEffect._bloomBoost * modelData.b) * ShellSettings.glowStrength)
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent"            }
                GradientStop { position: 1.0; color: _lineEffect._effectColor }
            }
        }
    }

    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        height: 8
        antialiasing: false
        visible: !_ul.wrapFloating && _lineEffect._glowEnabled && ShellSettings.underlineScreenshotGlow && _lineEffect._shotActive
        opacity: Math.min(0.85, _lineEffect._screenshotGlow * 0.34 * _lineEffect._screenshotStrength)

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: _lineEffect._screenshotColor }
        }
    }
    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.leftMargin:  _ul.wrapRadius
        anchors.rightMargin: _ul.wrapRadius
        anchors.bottom: parent.bottom
        height: 1
        antialiasing: false
        visible: !_ul.wrapFloating && _lineEffect._glowEnabled && ShellSettings.underlineScreenshotGlow && _lineEffect._shotActive
        opacity: Math.min(1.0, _lineEffect._screenshotGlow * 0.78 * _lineEffect._screenshotStrength)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent"          }
            GradientStop { position: 0.25; color: Theme.withAlpha(_lineEffect._screenshotColor, 0.6) }
            GradientStop { position: 0.5;  color: _lineEffect._screenshotColor }
            GradientStop { position: 0.75; color: Theme.withAlpha(_lineEffect._screenshotColor, 0.6) }
            GradientStop { position: 1.0;  color: "transparent"          }
        }
    }

}
