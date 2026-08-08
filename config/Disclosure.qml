import QtQuick

MotionBehavior {
    id: root

    property bool expanded: true
    property int enterEasing: Easing.OutQuart
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
        duration: expanded ? Motion.medium : Motion.fast
        easing.type: expanded ? enterEasing : Easing.InCubic
    }
}
