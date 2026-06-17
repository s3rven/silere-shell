import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null   // ShellScreen this bar sits on, for menu placement

    glyph:      Audio.icon
    glyphColor: Audio.muted ? Theme.subtext : Theme.text
    textColor:  Theme.subtext
    cursorShape: Audio.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
    // Icon signals mute; reserveText pins width to "100%" so it doesn't jitter.
    reserveText: "100%"
    text: !Audio.ready ? ""
        : (ShellSettings.valuesOnHover && !hoverActive) ? ""
        : (Math.round(Audio.effectiveVolume * 100) + "%")

    WheelHandler {
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

    pressed: _tap.pressed && Audio.ready

    TapHandler {
        id: _tap
        acceptedButtons: Qt.LeftButton
        onTapped: Audio.toggleMute()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: MenuState.toggleAt(root.mapToItem(null, root.width / 2, 0).x, root.screen)
    }
}
