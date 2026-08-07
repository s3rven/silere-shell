import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowVolume
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    opacity: _baseOpacity
    visible: layoutVisible

    MotionBehavior on _baseOpacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    glyph:      Audio.icon
    glyphColor: Audio.muted ? Theme.subtext : Theme.text
    textColor:  Theme.subtext
    interactive: Audio.ready
    accessibleName: !Audio.ready ? "Volume unavailable"
        : Audio.muted ? `Volume muted, ${Math.round(Audio.effectiveVolume * 100)} percent`
        : `Volume ${Math.round(Audio.effectiveVolume * 100)} percent`
    accessibleDescription: "Scroll to adjust volume. Activate to toggle mute."
    reserveText: "100%"
    text: !Audio.ready ? ""
        : (ShellSettings.valuesOnHover && !expanded) ? ""
        : (Math.round(Audio.effectiveVolume * 100) + "%")
    levelValue: Audio.ready ? Audio.uiVolume : -1
    levelVisible: Audio.ready && ShellSettings.valuesOnHover && ShellSettings.hoverLevelBar && !expanded
    levelColor: Audio.muted ? Theme.subtext : Theme.accent

    Accessible.role: Accessible.Slider
    Accessible.focusable: Audio.ready
    Accessible.onIncreaseAction: if (Audio.ready) {
        Audio.bumpBy(Audio.stepPct)
    }
    Accessible.onDecreaseAction: if (Audio.ready) {
        Audio.bumpBy(-Audio.stepPct)
    }

    Keys.onLeftPressed:  event => { if (Audio.ready) { Audio.bumpBy(-Audio.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onDownPressed:  event => { if (Audio.ready) { Audio.bumpBy(-Audio.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onRightPressed: event => { if (Audio.ready) { Audio.bumpBy(Audio.stepPct);  event.accepted = true } else event.accepted = false }
    Keys.onUpPressed:    event => { if (Audio.ready) { Audio.bumpBy(Audio.stepPct);  event.accepted = true } else event.accepted = false }
    Keys.onPressed: event => {
        if (!Audio.ready) return
        if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            Audio.bumpBy((event.key === Qt.Key_PageUp ? 1 : -1) * Audio.stepPct * 5)
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            Audio.setVolume(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            Audio.setVolume(1)
            event.accepted = true
        }
    }

    WheelHandler {
        enabled: Audio.ready
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!Audio.ready) return
            const n = Scroll.processControlWheel(event, "audio")
            if (n !== 0) Audio.bumpBy(n * Audio.stepPct)
        }
    }

    HoverHandler { cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }

    pressed: _tap.pressed && Audio.ready
    onActivated: Audio.toggleMute()

    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
