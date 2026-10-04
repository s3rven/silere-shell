import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowMic && Audio.micActive
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    readonly property bool _live: Audio.micActive && !Audio.micMuted
    readonly property bool _canSwitch: Audio.sourceCount > 1

    collapsed: !show
    opacity: _baseOpacity
    visible: layoutVisible

    MotionBehavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    scale: root.show ? 1.0 : 0.88
    transformOrigin: Item.Center
    MotionBehavior on scale {
        id: _scaleMotion
        NumberAnimation {
            duration: _scaleMotion.targetValue >= 1 ? Motion.medium : Motion.fast
            easing.type: _scaleMotion.targetValue >= 1 ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.7
        }
    }

    glyph:      Audio.micIcon
    glyphColor: root._live ? Theme.error : Theme.subtext
    textColor:  Theme.subtext
    interactive: Audio.micReady
    reserveText: "100%"
    accessibleName: {
        if (!Audio.micReady) return "Microphone"
        const parts = [Audio.micMuted ? "Microphone muted" : "Microphone in use"]
        if (Audio.captureSummary.length > 0) parts.push(Audio.captureSummary)
        if (!Audio.micMuted) parts.push(Math.round(Audio.micVolume * 100) + "%")
        if (Audio.sourceName.length > 0) parts.push(Audio.sourceName)
        return parts.join(", ")
    }
    text: !Audio.micReady ? ""
        : (ShellSettings.valuesOnHover && !expanded) ? ""
        : (Math.round(Audio.micVolume * 100) + "%")
    levelValue: Audio.micReady ? Audio.micVolume : -1
    levelVisible: Audio.micReady && ShellSettings.valuesOnHover
        && ShellSettings.hoverLevelBar && !expanded
    levelColor: Audio.micMuted ? Theme.subtext : Theme.error

    WheelHandler {
        enabled: Audio.micReady
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!Audio.micReady) return
            const n = Scroll.processLevelWheel(event, "microphone")
            if (n !== 0) Audio.micBumpBy(n * Audio.stepPct)
        }
    }

    pressed: _tap.pressed && Audio.micReady
    onActivated: Audio.toggleMicMute()

    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }

    TapHandler {
        enabled: root.interactive && (Audio.hasSoundSettings || root._canSwitch)
        acceptedButtons: (Audio.hasSoundSettings ? Qt.RightButton : Qt.NoButton)
            | (root._canSwitch ? Qt.MiddleButton : Qt.NoButton)
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onSingleTapped: (point, button) => {
            if (button === Qt.RightButton) Audio.openSoundSettings()
            else Audio.cycleSource()
        }
    }
}
