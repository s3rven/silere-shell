import QtQuick

MotionBehavior {
    id: root

    property bool expanded: true
    property int enterEasing: Easing.BezierSpline
    property int exitEasing: Easing.BezierSpline
    property var enterCurve: Motion.emphasizedDecel
    property var exitCurve: Motion.emphasizedAccel
    // a mutually-exclusive pair must share one curve in both directions, or the
    // expanding sibling outruns the collapsing one and their summed height bulges
    property bool symmetric: false
    readonly property bool _enter: root.expanded || root.symmetric
    property bool _geometryReady: false
    property Timer _geometrySettle: Timer {
        interval: 0
        onTriggered: root._geometryReady = true
    }

    // a fresh Column/Loader reports 0 before its first implicitHeight; arm a pass later or first use plays a fake reveal
    gate: root._geometryReady
    Component.onCompleted: root._geometrySettle.start()
    Component.onDestruction: root._geometrySettle.stop()

    NumberAnimation {
        duration: root._enter ? Motion.medium : Motion.fast
        easing.type: root._enter ? root.enterEasing : root.exitEasing
        easing.bezierCurve: root._enter ? root.enterCurve : root.exitCurve
    }
}
