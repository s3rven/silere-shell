import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowMic && Audio.micActive
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    // muted as the apps hear it while one records; with none, the default's own mute
    readonly property bool _heardMuted: Audio.micActive ? !Audio.micHeard : Audio.micMuted
    readonly property bool _live: Audio.micActive && Audio.micHeard
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

    // all of it follows what the apps hear, not the default's mute alone: a red glyph struck through read both ways
    glyph:      !Audio.micReady || root._heardMuted ? "󰍭" : "󰍬"
    glyphColor: root._live ? Theme.barError : Theme.barSubtext
    textColor:  Theme.barSubtext
    interactive: Audio.micReady
    reserveText: "00%"
    accessibleName: {
        if (!Audio.micReady) return "Microphone"
        const parts = [root._heardMuted ? "Microphone muted" : "Microphone in use"]
        if (Audio.captureSummary.length > 0) parts.push(Audio.captureSummary)
        if (!root._heardMuted) parts.push(Math.round(Audio.micVolume * 100) + "%")
        if (Audio.sourceName.length > 0) parts.push(Audio.sourceName)
        return parts.join(", ")
    }
    readonly property string _level: Math.round(Audio.micVolume * 100) + "%"
    text: !Audio.micReady || (ShellSettings.valuesOnHover && !expanded) ? ""
        : (expanded && root._heardMuted ? "Muted" : root._level)
            + (expanded && Audio.captureSummary.length > 0 ? " · " + Audio.captureSummary : "")
    maxTextWidth: compact ? 150 : 260
    levelValue: Audio.micReady ? Audio.micVolume : -1
    levelVisible: Audio.micReady && ShellSettings.valuesOnHover
        && ShellSettings.hoverLevelBar && !expanded
    levelColor: root._heardMuted ? Theme.barSubtext : Theme.barError

    wheelKey: "microphone:" + root + ":" + (Audio.source ? String(Audio.source.id) : "")

    WheelHandler {
        enabled: Audio.micReady && root.hoverEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!Audio.micReady || !root.hoverEnabled) return
            const n = Scroll.processLevelWheel(event, root.wheelKey)
            if (n !== 0) Audio.micBumpBy(n * Audio.stepPct)
        }
    }

    pressed: _tap.pressed && Audio.micReady
    onActivated: if (root.canActivate) Audio.toggleMicMute()

    TapHandler {
        id: _tap
        enabled: root.canActivate
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }

    TapHandler {
        enabled: root.canActivate && (Audio.hasSoundSettings || root._canSwitch)
        acceptedButtons: (Audio.hasSoundSettings ? Qt.RightButton : Qt.NoButton)
            | (root._canSwitch ? Qt.MiddleButton : Qt.NoButton)
        gesturePolicy: TapHandler.ReleaseWithinBounds
        // every middle click steps once, a quick second one included; a double right click opens one window
        onTapped: (point, button) => { if (root.canActivate && button === Qt.MiddleButton) Audio.cycleSource() }
        onSingleTapped: (point, button) => { if (root.canActivate && button === Qt.RightButton) Audio.openSoundSettings() }
    }
}
