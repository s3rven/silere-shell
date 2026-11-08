import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    property var screen: null

    readonly property bool autoHidden: ShellSettings.batteryAutoHide && !Battery.onBattery
    readonly property bool show: ShellSettings.barShowBattery && Battery.available && !autoHidden
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    collapsed: !show

    glyph:          Battery.icon
    accessibleName: {
        if (!Battery.available) return "Battery"
        const parts = []
        if (Battery.label.length > 0)       parts.push(Battery.label)
        if (Battery.statusLabel.length > 0) parts.push(Battery.statusLabel)
        return parts.length > 0 ? "Battery " + parts.join(", ") : "Battery"
    }
    glyphColor:     Battery.barIconColor
    textColor:      Theme.barSubtext
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "00%"
    levelValue:     Battery.pct > 0 ? Battery.pct / 100 : -1
    levelVisible:   Battery.pct > 0 && ShellSettings.valuesOnHover
                    && ShellSettings.hoverLevelBar && !expanded
    levelColor:     Qt.colorEqual(Battery.barIconColor, Theme.barText) ? Theme.barAccent : Battery.barIconColor
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: layoutVisible
    interactive: show
    pressed: _tap.pressed
    onActivated: if (batteryPill.canActivate) MenuState.showHomeAt("power", batteryPill, batteryPill.screen)

    TapHandler {
        id: _tap
        enabled: batteryPill.canActivate
        onTapped: batteryPill.activated()
    }

    MotionBehavior on _baseOpacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

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
