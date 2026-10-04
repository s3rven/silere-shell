pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    required property bool shown
    property bool retained: root.shown
    property Component content: null
    // the outer rail clips the drawer to its live width
    property real revealedWidth: width
    readonly property alias item: _loader.item
    readonly property bool _contentReady: _loader.status === Loader.Ready
    readonly property bool _present: root.shown && root._contentReady
        && root.revealedWidth >= Math.min(root.width, 28)

    property real _slide: root._present ? 0 : -Motion.pageOffset
    opacity: root._present ? 1 : 0
    visible: opacity > 0.001
    enabled: root._present
    transform: Translate { x: root._slide }

    MotionBehavior on opacity {
        id: _drawerFade
        NumberAnimation {
            duration: _drawerFade.targetValue > 0.5 ? Motion.pageIn : Motion.pageOut
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
