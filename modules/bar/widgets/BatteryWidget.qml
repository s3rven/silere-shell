import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    // opt-in: drop the indicator while charging/full (uninformative then); show also drives the separator dot
    readonly property bool autoHidden: ShellSettings.batteryAutoHide && (Battery.charging || Battery.full)
    readonly property bool show: ShellSettings.barShowBattery && Battery.available && !autoHidden
    property real _baseOpacity: show ? 1.0 : 0.0

    glyph:          Battery.icon
    glyphPixelSize: Settings.fontSize + 3   // horizontal battery glyph reads optically short
    glyphColor:     Battery.iconColor
    textColor:      Battery.iconColor
    accessibleName: !show ? "Battery unavailable"
        : `Battery ${Battery.label}${Battery.statusLabel.length > 0 ? `, ${Battery.statusLabel}` : ""}${Battery.timeLabel.length > 0 ? `, ${Battery.timeLabel}` : ""}`
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "100%"
    // status pill: Tab-reachable so AT can read it, Enter/Space stay no-ops
    activeFocusOnTab: show
    Accessible.focusable: true
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: _baseOpacity > 0

    Behavior on _baseOpacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    text: {
        if (expanded) {
            if (Battery.timeLabel.length > 0)
                return Battery.label + " · " + Battery.timeLabel
            if (Battery.statusLabel.length > 0)
                return Battery.label + " · " + Battery.statusLabel
            return Battery.label
        }
        // battery is status not a control — always shown, even when valuesOnHover hides the adjustable levels
        return Battery.label
    }
}
