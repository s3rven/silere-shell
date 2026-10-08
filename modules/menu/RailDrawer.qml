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
    property real _heldWidth: 0
    property bool _holdLayout: false

    function holdLayout(): void {
        if (root._holdLayout) return
        root._heldWidth = _loader.width
        root._holdLayout = true
    }

    onShownChanged: {
        if (root.shown) root._holdLayout = false
        else root.holdLayout()
    }
    Component.onCompleted: if (!root.shown) root.holdLayout()

    property real _slide: root._present ? 0 : -Motion.pageOffset
    opacity: root._present ? 1 : 0
    visible: opacity > 0.001
    enabled: root._present
    transform: Translate { x: root._slide }

    MotionBehavior on opacity {
        id: _drawerFade
        NumberAnimation {
            duration: _drawerFade.targetValue > 0.5 ? Motion.pageIn : Motion.pageOut
            easing.type: _drawerFade.targetValue > 0.5 ? Easing.OutQuad : Easing.InQuad
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
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // Keep the departing labels at their old wrap width while the outer
        // rail clips them away. Reflow only when the drawer returns.
        width: root._holdLayout ? root._heldWidth : root.width
        active: root.retained
        // Showing an in-progress hover preload must not force its remaining
        // incubation onto the first frame of the panel transition.
        asynchronous: true
        sourceComponent: root.content
    }
}
