import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    property var screen: null   // ShellScreen this bar sits on, for menu placement

    // Opt-in: drop the indicator while charging or full, since it's not telling
    // you anything useful then. shown also drives the separator dot.
    readonly property bool autoHidden: ShellSettings.batteryAutoHide && (Battery.charging || Battery.full)
    readonly property bool shown: Battery.available && !autoHidden
    property real _baseOpacity: shown ? 1.0 : 0.0

    glyph:          Battery.icon
    glyphColor:     Battery.iconColor
    textColor:      Battery.iconColor
    // Battery has no action of its own (no mute/refresh equivalent), so unlike
    // its siblings it keeps a click handler — opening the menu — instead of
    // going fully inert. The lone exception; see settings-menu-single-entry-point.
    interactive:    shown
    accessibleName: !shown ? "Battery unavailable"
        : `Battery ${Battery.label}${Battery.statusLabel.length > 0 ? `, ${Battery.statusLabel}` : ""}${Battery.timeLabel.length > 0 ? `, ${Battery.timeLabel}` : ""}`
    accessibleDescription: "Activate to open the menu."
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "100%"
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: _baseOpacity > 0

    Behavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    text: {
        if (expanded) {
            if (Battery.timeLabel.length > 0)
                return Battery.label + " · " + Battery.timeLabel
            if (Battery.statusLabel.length > 0)
                return Battery.label + " · " + Battery.statusLabel
            return Battery.label
        }
        return ShellSettings.valuesOnHover ? "" : Battery.label
    }

    pressed: _tap.pressed
    onActivated: MenuState.toggleAt(batteryPill.mapToItem(null, batteryPill.width / 2, 0).x, batteryPill.screen)

    TapHandler {
        id: _tap
        enabled: batteryPill.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: batteryPill.activated()
    }
}
