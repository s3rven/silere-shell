import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    readonly property bool autoHidden: ShellSettings.batteryAutoHide && (Battery.charging || Battery.full)
    readonly property bool show: ShellSettings.barShowBattery && Battery.available && !autoHidden
    property real _baseOpacity: show ? 1.0 : 0.0

    glyph:          Battery.icon
    glyphPixelSize: Settings.iconSize + 3
    glyphColor:     Battery.iconColor
    textColor:      Battery.iconColor
    accessibleName: !show ? "Battery unavailable"
        : `Battery ${Battery.label}${Battery.statusLabel.length > 0 ? `, ${Battery.statusLabel}` : ""}${Battery.timeLabel.length > 0 ? `, ${Battery.timeLabel}` : ""}`
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "100%"
    levelValue:     Battery.pct > 0 ? Battery.pct / 100 : -1
    levelVisible:   Battery.pct > 0 && ShellSettings.valuesOnHover
                    && ShellSettings.hoverLevelBar && !expanded
    levelColor:     Battery.iconColor
    activeFocusOnTab: show
    Accessible.focusable: true
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: _baseOpacity > 0

    Behavior on _baseOpacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    text: {
        if (ShellSettings.valuesOnHover && !expanded)
            return ""
        if (!expanded)
            return Battery.label

        const detail = Battery.timeLabel.length > 0 ? Battery.timeLabel : Battery.statusLabel
        if (Battery.label.length === 0)
            return detail
        if (detail.length > 0)
            return Battery.label + " · " + detail
        return Battery.label
    }
}
