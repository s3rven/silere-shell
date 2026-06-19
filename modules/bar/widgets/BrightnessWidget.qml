import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null   // ShellScreen this bar sits on, for menu placement

    readonly property bool canControl: Brightness.toolAvailable && Brightness.maxBrightness > 0

    opacity:     canControl ? 1.0 : 0.45
    visible: Brightness.maxBrightness > 0
    glyph:           Brightness.icon
    glyphColor:      canControl ? Theme.text : Theme.subtext
    reserveText: "100%"
    text:        (ShellSettings.valuesOnHover && !hoverActive) ? ""
                 : (canControl ? Brightness.label : "—")
    textColor:   Theme.subtext
    cursorShape: canControl ? Qt.PointingHandCursor : Qt.ArrowCursor

    Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!root.canControl) return
            const n = Scroll.processControlWheel(event, "brightness")
            if (n !== 0) Brightness.bumpBy(n * 5)
        }
    }
}
