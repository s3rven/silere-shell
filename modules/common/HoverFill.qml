import QtQuick
import "../../config"

// a popup row's hover and press fill, on the menu rows' timing: a press lands in 90 ms and a
// hover leaves slower than it came, where one colour fade gave every change the same 160 ms
Rectangle {
    id: root

    property bool hovered: false
    property bool pressed: false
    property real hoverOpacity: 0.08
    property real pressOpacity: 0.13

    radius: Theme.radiusControl
    antialiasing: true
    color: Theme.menuHover
    opacity: pressed ? pressOpacity : hovered ? hoverOpacity : 0

    MotionBehavior on opacity {
        id: _feedback
        NumberAnimation {
            duration: _feedback.targetValue > root.hoverOpacity ? Motion.press
                : _feedback.targetValue > 0 ? Motion.hoverIn : Motion.hoverOut
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
        }
    }
    ColorFade on color {}
}
