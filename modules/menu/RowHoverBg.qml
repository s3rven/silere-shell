import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property real  topRadius:    0
    property real  bottomRadius: 0
    property real  cardInset:    1
    property bool  active:       false
    property bool  focusActive:  false
    property real  fillOpacity:  0.07
    property color fillColor:    Theme.menuHover
    property color focusColor:   Theme.accent

    Rectangle {
        readonly property real _topR: Math.max(0, root.topRadius    - root.cardInset)
        readonly property real _botR: Math.max(0, root.bottomRadius - root.cardInset)

        anchors.fill:         parent
        anchors.leftMargin:   root.cardInset
        anchors.rightMargin:  root.cardInset
        anchors.topMargin:    root.topRadius    > 0 ? root.cardInset : 0
        anchors.bottomMargin: root.bottomRadius > 0 ? root.cardInset : 0

        topLeftRadius:     _topR
        topRightRadius:    _topR
        bottomLeftRadius:  _botR
        bottomRightRadius: _botR
        antialiasing:      _topR > 0 || _botR > 0

        color:   root.fillColor
        opacity: root.active ? root.fillOpacity : 0
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: root.cardInset + 2
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: Math.max(12, Math.min(22, parent.height - 16))
        radius: 1
        color: root.focusColor
        opacity: root.focusActive ? 0.88 : 0
        scale: root.focusActive ? 1 : 0.55
        transformOrigin: Item.Center
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast }
        }
        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }
    }
}
