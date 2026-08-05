import QtQuick
import "../../../config"

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
        Disclosure on height { expanded: root.open }
    }

    CollapsibleSection {
        id: _section
        width: root.width
        expanded: root.open

        Loader {
            width: parent.width
            // the section animates to 0, not this Loader's parent - the content column never shrinks
            active: root.open || _section.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: root.content
        }
    }
}
