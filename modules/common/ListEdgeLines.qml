import QtQuick
import "../../config"

Item {
    id: root

    required property Flickable list
    property real maxOpacity: 1.0
    property color lineColor: Theme.menuDivider

    Hairline {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, root.list.contentY / 28.0)
        visible: opacity > 0.001
        color: root.lineColor
    }

    Hairline {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, Math.max(0,
            (root.list.contentHeight - root.list.contentY - root.list.height) / 28.0))
        visible: opacity > 0.001
        color: root.lineColor
    }
}
