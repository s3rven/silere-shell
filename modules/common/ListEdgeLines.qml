import QtQuick
import "../../config"

Item {
    id: root

    required property Flickable list
    property real ramp: 28.0
    property real maxOpacity: 1.0
    property color lineColor: Theme.menuDivider

    Hairline {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, root.list.contentY / root.ramp)
        visible: opacity > 0.001
        color: root.lineColor
    }

    Hairline {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, Math.max(0,
            (root.list.contentHeight - root.list.contentY - root.list.height) / root.ramp))
        visible: opacity > 0.001
        color: root.lineColor
    }
}
