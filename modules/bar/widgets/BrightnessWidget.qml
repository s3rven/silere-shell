import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool canControl: Brightness.toolAvailable && Brightness.maxBrightness > 0
    readonly property bool show: ShellSettings.barShowBrightness && Brightness.maxBrightness > 0

    opacity:     canControl ? 1.0 : 0.45
    visible: show
    glyph:           Brightness.icon
    glyphColor:      canControl ? Theme.text : Theme.subtext
    reserveText: "100%"
    text:        (ShellSettings.valuesOnHover && !expanded) ? ""
                 : (canControl ? Brightness.label : "—")
    textColor:   Theme.subtext
    levelValue: canControl ? Brightness.pct : -1
    levelVisible: canControl && ShellSettings.valuesOnHover && ShellSettings.hoverLevelBar && !expanded
    levelColor: Theme.accent
    accessibleName: canControl ? `Brightness ${Brightness.percent} percent` : "Brightness unavailable"
    accessibleDescription: "Scroll to adjust brightness."

    activeFocusOnTab: canControl
    Accessible.role: Accessible.Slider
    Accessible.focusable: canControl

    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    HoverHandler { cursorShape: root.canControl ? Qt.PointingHandCursor : Qt.ArrowCursor }

    Keys.onLeftPressed:  event => { if (canControl) { Brightness.bumpBy(-Brightness.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onDownPressed:  event => { if (canControl) { Brightness.bumpBy(-Brightness.stepPct); event.accepted = true } else event.accepted = false }
    Keys.onRightPressed: event => { if (canControl) { Brightness.bumpBy(Brightness.stepPct);  event.accepted = true } else event.accepted = false }
    Keys.onUpPressed:    event => { if (canControl) { Brightness.bumpBy(Brightness.stepPct);  event.accepted = true } else event.accepted = false }

    WheelHandler {
        enabled: root.canControl
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!root.canControl) return
            const n = Scroll.processControlWheel(event, "brightness")
            if (n !== 0) Brightness.bumpBy(n * Brightness.stepPct)
        }
    }
}
