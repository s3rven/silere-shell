import QtQuick
import "../../config"

// the bar's hover capsule, one law for every clickable widget: eased in a little quicker than it leaves, and settling
// a pixel out to its edge as it arrives. An inset, not a scale: 0.96 nudged a pill a pixel a side but zoomed a wide
// media title by six, and the clock and media title had drifted to a linear fade with no settle at all
Rectangle {
    id: cap

    // the pointer, already gated on barHoverHighlight by the widget
    property bool hot: false
    property bool pressed: false
    // a surface the widget opened is showing
    property bool selected: false
    property bool gate: true

    property real _inset: cap.pressed ? 0.4 : cap.hot || cap.selected ? 0 : 1

    anchors.centerIn: parent
    width: parent ? parent.width - cap._inset * 2 : 0
    height: Metrics.barRowHeight - cap._inset * 2
    radius: Metrics.hoverRadiusFor(height)
    color: cap.pressed ? Theme.barPressed : cap.selected ? Theme.barSelected : Theme.barHover
    opacity: cap.hot || cap.pressed || cap.selected ? 1 : 0
    visible: opacity > 0.001

    MotionBehavior on opacity {
        id: _fade
        gate: cap.gate
        NumberAnimation {
            duration: _fade.targetValue > 0.5 ? Motion.hoverIn : Motion.hoverOut
            easing.type: Easing.OutCubic
        }
    }
    MotionBehavior on _inset {
        id: _settle
        gate: cap.gate
        NumberAnimation {
            duration: _settle.targetValue <= 0 ? Motion.hoverIn
                : _settle.targetValue < 1 ? Motion.press : Motion.hoverOut
            easing.type: Easing.OutCubic
        }
    }
    ColorFade on color { gate: cap.gate }
}
