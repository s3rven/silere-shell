import QtQuick

MotionBehavior {
    property bool expanded: true
    property int enterEasing: Easing.OutQuart

    NumberAnimation {
        duration: expanded ? Motion.medium : Motion.fast
        easing.type: expanded ? enterEasing : Easing.InCubic
    }
}
