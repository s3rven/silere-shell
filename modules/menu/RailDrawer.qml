pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    required property bool shown
    property bool retained: root.shown
    property Component content: null
    readonly property alias item: _loader.item

    property real _slide: root.shown ? 0 : -Motion.pageOffset
    opacity: root.shown ? 1 : 0
    visible: opacity > 0.001
    enabled: root.shown
    transform: Translate { x: root._slide }

    MotionBehavior on opacity {
        id: _drawerFade
        NumberAnimation {
            duration: _drawerFade.targetValue > 0.5 ? Motion.ms(130) : Motion.ms(90)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: _drawerFade.targetValue > 0.5
                ? Motion.standardDecel : Motion.standardAccel
        }
    }
    MotionBehavior on _slide {
        id: _slideMotion
        NumberAnimation {
            duration: _slideMotion.targetValue >= 0 ? Motion.panelResize : Motion.panelCollapse
            easing.type: Easing.BezierSpline
            easing.bezierCurve: _slideMotion.targetValue >= 0
                ? Motion.emphasizedDecel : Motion.emphasizedAccel
        }
    }
    Loader {
        id: _loader
        anchors.fill: parent
        active: root.retained
        asynchronous: !root.shown
        sourceComponent: root.content
    }
}
