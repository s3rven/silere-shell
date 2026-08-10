import QtQuick

Column {
    id: root

    property bool open: false
    property Component content: null

    width: parent ? parent.width : 0
    spacing: 0

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
