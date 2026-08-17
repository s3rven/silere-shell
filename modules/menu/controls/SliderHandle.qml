import QtQuick
import "../../../config"
import "../../common"

Rectangle {
    id: root

    property color fillColor: Theme.accent
    property color outlineColor: "transparent"
    property bool hovered: false
    property bool pressed: false
    property bool hoverGrow: true
    property bool animate: true

    radius: 4
    antialiasing: true
    color: root.fillColor
    // grow via scale, not width: a re-layouted odd width lands the centre on a half-pixel and the handle visibly shifts under fractional scaling
    scale: !root.hoverGrow ? 1.0
         : root.pressed ? 0.92
         : root.hovered ? 1.06 : 1.0
    transformOrigin: Item.Center

    // scale magnitudes stay larger than Motion.hoverScale: on a 14px handle 1.8% is a sub-pixel no-op
    MotionBehavior on scale {
        gate: root.animate
        NumberAnimation {
            duration: root.pressed ? Motion.press
                : root.hovered ? Motion.hoverIn : Motion.hoverOut
            easing.type: Easing.OutCubic
        }
    }
    ColorFade on color { gate: root.animate && !root.pressed }

    // Rectangle.border over-weights the corners and, on a scaled item, smears into a halo
    OutlineBorder {
        radius: root.radius
        outlineWidth: 1
        outlineColor: root.outlineColor
        ColorFade on outlineColor { gate: root.animate }
    }
}
