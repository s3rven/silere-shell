import QtQuick
import "../../config"
import "../../services"

Column {
    id: root

    property bool open: false
    property int gap: 8
    property Component content: null

    width: parent ? parent.width : 0
    spacing: 0

    Item {
        width: 1
        height: root.open ? root.gap : 0
        Behavior on height {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration: Motion.medium
                easing.type: root.open ? Easing.OutQuart : Easing.InCubic
            }
        }
    }

    CollapsibleSection {
        id: _section
        width: root.width
        expanded: root.open

        Loader {
            width: parent.width
            // the section animates to 0, not this Loader's parent — that's the
            // content column, whose height never shrinks
            active: root.open || _section.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: root.content
        }
    }
}
