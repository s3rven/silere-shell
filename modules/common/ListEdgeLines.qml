import QtQuick
import "../../config"

Item {
    id: root

    required property Flickable list
    property real maxOpacity: 1.0
    property color lineColor: Theme.menuDivider

    readonly property real _overflow: Math.max(0, list.contentHeight - list.height)
    readonly property real _offset: Math.max(0,
        Math.min(_overflow, list.contentY - list.originY))

    Hairline {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, root._offset / 28.0)
        visible: opacity > 0.001
        color: root.lineColor
    }

    Hairline {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        opacity: root.maxOpacity * Math.min(1.0, (root._overflow - root._offset) / 28.0)
        visible: opacity > 0.001
        color: root.lineColor
    }
}
