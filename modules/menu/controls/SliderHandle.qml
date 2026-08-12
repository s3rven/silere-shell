import QtQuick
import "../../../config"
import "../../../services"

Rectangle {
    id: root

    property color fillColor: Theme.accent
    property bool focused: false
    property bool hovered: false
    property bool pressed: false
    property bool hoverGrow: true
    property bool animate: true
    property color focusRingColor: Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)

    radius: 3
    antialiasing: true
    color: root.fillColor
    // grow via scale, not width: a re-layouted odd width lands the centre on a half-pixel and the handle visibly shifts under fractional scaling
    scale: !root.hoverGrow ? 0.90
         : root.pressed ? 0.92
         : (root.hovered || root.focused) ? 1.05 : 1.0
    transformOrigin: Item.Center

    border.width: root.focused ? 2 : 1
    border.color: root.focused ? root.focusRingColor
        : Theme.withAlpha(Theme.text,
            ShellSettings.highContrast ? 0.72
            : root.hovered || root.pressed ? 0.52 : 0.30)

    MotionBehavior on scale {
        gate: root.animate
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }
    MotionBehavior on border.color {
        gate: root.animate
        ColorAnimation { duration: Motion.fast }
    }
    ColorFade on color { gate: root.animate && !root.pressed }
}
