pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    required property bool shown
    property bool retained: root.shown
    property int slideMs: Motion.panelResize
    property var slideCurve: Motion.emphasizedDecel
    property Component content: null
    readonly property alias item: _loader.item

    property real _slide: root.shown ? 0 : -Motion.pageOffset
    opacity: root.shown ? 1 : 0
    visible: opacity > 0.001
    enabled: root.shown
    transform: Translate { x: root._slide }

    MotionBehavior on opacity {
        NumberAnimation {
            duration: root.shown ? Motion.ms(130) : Motion.ms(90)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown
                ? Motion.standardDecel : Motion.standardAccel
        }
    }
    MotionBehavior on _slide {
        NumberAnimation {
            duration: root.slideMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.slideCurve
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
