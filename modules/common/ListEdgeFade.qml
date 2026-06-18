import QtQuick
import "../../config"

// Top + bottom overflow cues for a scrollable list: each edge fade ramps in as
// the list scrolls away from it. Place over the list's visible area (anchors.fill
// or explicit geometry) and point `list` at the ListView/Flickable to track.
Item {
    id: root
    required property Flickable list
    property color fadeColor: Theme.popup
    property int   thickness: 22
    property real  ramp:      18.0

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.thickness
        opacity: Math.min(1.0, root.list.contentY / root.ramp)
        visible: opacity > 0.001
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fadeColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: root.thickness
        opacity: Math.min(1.0, Math.max(0,
            (root.list.contentHeight - root.list.contentY - root.list.height) / root.ramp))
        visible: opacity > 0.001
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: root.fadeColor }
        }
    }
}
