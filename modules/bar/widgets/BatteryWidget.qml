import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    // Opt-in: drop the indicator while charging or full, since it's not telling
    // you anything useful then. shown also drives the separator dot.
    readonly property bool autoHidden: ShellSettings.batteryAutoHide && (Battery.charging || Battery.full)
    readonly property bool shown: Battery.available && !autoHidden
    property real _baseOpacity: shown ? 1.0 : 0.0

    glyph:          Battery.icon
    glyphColor:     Battery.iconColor
    textColor:      Battery.iconColor
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "100%"
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: opacity > 0

    Behavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    text: {
        if (hoverActive) {
            if (Battery.timeLabel.length > 0)
                return Battery.label + " · " + Battery.timeLabel
            if (Battery.statusLabel.length > 0)
                return Battery.label + " · " + Battery.statusLabel
            return Battery.label
        }
        return ShellSettings.valuesOnHover ? "" : Battery.label
    }
}
