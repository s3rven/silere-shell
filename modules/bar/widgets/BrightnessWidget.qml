import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool canControl: Brightness.toolAvailable && Brightness.maxBrightness > 0

    opacity:     canControl ? 1.0 : 0.45
    visible: Brightness.maxBrightness > 0
    glyph:           Brightness.icon
    glyphColor:      canControl ? Theme.text : Theme.subtext
    reserveText: "100%"
    text:        (ShellSettings.valuesOnHover && !expanded) ? ""
                 : (canControl ? Brightness.label : "—")
    textColor:   Theme.subtext
    accessibleName: canControl ? `Brightness ${Brightness.percent} percent` : "Brightness unavailable"
    accessibleDescription: "Scroll to adjust brightness."

    Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    WheelHandler {
        enabled: root.canControl
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!root.canControl) return
            const n = Scroll.processControlWheel(event, "brightness")
            if (n !== 0) Brightness.bumpBy(n * 5)
        }
    }
}
