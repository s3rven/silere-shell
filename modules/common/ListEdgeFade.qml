import QtQuick
import "../../config"

Item {
    id: root
    required property Flickable list
    property color fadeColor: Theme.popup
    property int   thickness: 14
    property real  ramp:      28.0
    property real  maxOpacity: 0.58

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.thickness
        opacity: root.maxOpacity * Math.min(1.0, root.list.contentY / root.ramp)
        visible: opacity > 0.001
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fadeColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: root.thickness
        opacity: root.maxOpacity * Math.min(1.0, Math.max(0,
            (root.list.contentHeight - root.list.contentY - root.list.height) / root.ramp))
        visible: opacity > 0.001
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: root.fadeColor }
        }
    }
}
