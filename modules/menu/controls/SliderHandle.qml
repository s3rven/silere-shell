import QtQuick
import Quickshell
import "../../../config"
import "../../common"

Rectangle {
    id: root

    property color fillColor: Theme.accent
    property color outlineColor: "transparent"
    property real outlineWidth: 1
    property bool hovered: false
    property bool pressed: false
    property bool hoverGrow: true
    property bool animate: true

    // proportional, not fixed: 4px on the default 14px thumb is the squircle Silere uses, but the same 4px on a smaller thumb rounds it into a circle
    radius: Math.max(2, Math.round(Math.min(width, height) * 0.286))
    antialiasing: true
    color: root.fillColor
    // grow via scale, not width: a re-layouted odd width lands the centre on a half-pixel and the handle visibly shifts under fractional scaling
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    transform: PixelScale {
        item: root
        dpr: root._dpr
        animate: root.animate
        // pressed must round to more device pixels than hovered, or the held lift vanishes at 1.25
        factor: !root.hoverGrow ? 1.0
              : root.pressed ? 1.18
              : root.hovered ? 1.06 : 1.0
        duration: root.pressed ? Motion.press
            : root.hovered ? Motion.hoverIn : Motion.hoverOut
    }
    ColorFade on color { gate: root.animate && !root.pressed }

    // Rectangle.border over-weights the corners and, on a scaled item, smears into a halo
    OutlineBorder {
        radius: root.radius
        outlineWidth: root.outlineWidth
        outlineColor: root.outlineColor
        ColorFade on outlineColor { gate: root.animate }
    }
}
