import QtQuick
import "../../config"

Item {
    id: root

    property real  topRadius:    0
    property real  bottomRadius: 0
    property real  cardInset:    1
    property real  leftBleed:    0
    property bool  active:       false
    property bool  focusActive:  false
    property real  fillOpacity:  0.07
    property color fillColor:    Theme.menuHover
    property color focusColor:   Theme.accent

    Rectangle {
        readonly property real _topR: Math.max(0, root.topRadius    - root.cardInset)
        readonly property real _botR: Math.max(0, root.bottomRadius - root.cardInset)

        x:      -root.leftBleed + root.cardInset
        y:      root.topRadius > 0 ? root.cardInset : 0
        width:  Math.max(0, parent.width + root.leftBleed - root.cardInset * 2)
        height: Math.max(0, parent.height
            - (root.topRadius > 0 ? root.cardInset : 0)
            - (root.bottomRadius > 0 ? root.cardInset : 0))

        topLeftRadius:     _topR
        topRightRadius:    _topR
        bottomLeftRadius:  _botR
        bottomRightRadius: _botR
        antialiasing:      _topR > 0 || _botR > 0

        color:   root.fillColor
        opacity: root.active ? root.fillOpacity : 0
        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: root.cardInset + 2
        anchors.verticalCenter: parent.verticalCenter
        width: Metrics.menuMarkerWidth
        height: Math.min(Metrics.menuMarkerHeight,
            Math.max(1, parent.height - 8))
        radius: Metrics.menuMarkerRadius
        color: root.focusColor
        opacity: root.focusActive ? Metrics.menuMarkerOpacity : 0
        scale: root.focusActive ? 1 : 0.55
        transformOrigin: Item.Center
        visible: opacity > 0.001

        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }
        MotionBehavior on scale {
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }
    }
}
