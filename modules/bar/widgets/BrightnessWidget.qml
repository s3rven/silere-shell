import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool canControl: Brightness.controllable
    readonly property bool show: ShellSettings.barShowBrightness && canControl

    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    collapsed: !show
    opacity: _baseOpacity
    visible: layoutVisible
    glyph:           Brightness.icon
    glyphColor:      canControl ? Theme.text : Theme.subtext
    reserveText: "100%"
    text:        (ShellSettings.valuesOnHover && !expanded) ? ""
                 : (canControl ? Brightness.label : "—")
    textColor:   Theme.subtext
    interactive: canControl
    levelValue: canControl ? Brightness.pct : -1
    levelVisible: canControl && ShellSettings.valuesOnHover && ShellSettings.hoverLevelBar && !expanded
    levelColor: Theme.accent

    MotionBehavior on _baseOpacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

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
