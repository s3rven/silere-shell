import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null

    readonly property bool show: ShellSettings.barShowVolume
    visible: show

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

    Keys.onLeftPressed:  event => { if (Audio.ready) { if (Audio.muted) Audio.unmute(); Audio.bumpBy(-Audio.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onDownPressed:  event => { if (Audio.ready) { if (Audio.muted) Audio.unmute(); Audio.bumpBy(-Audio.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onRightPressed: event => { if (Audio.ready) { if (Audio.muted) Audio.unmute(); Audio.bumpBy(Audio.stepPct);  event.accepted = true } else event.accepted = false }
    Keys.onUpPressed:    event => { if (Audio.ready) { if (Audio.muted) Audio.unmute(); Audio.bumpBy(Audio.stepPct);  event.accepted = true } else event.accepted = false }
    Keys.onPressed: event => {
        if (!Audio.ready) return
        if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            if (Audio.muted) Audio.unmute()
            Audio.bumpBy((event.key === Qt.Key_PageUp ? 1 : -1) * Audio.stepPct * 5)
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            Audio.setVolume(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            if (Audio.muted) Audio.unmute()
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
            if (n !== 0) {
                if (Audio.muted) Audio.unmute()
                Audio.bumpBy(n * Audio.stepPct)
            }
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
