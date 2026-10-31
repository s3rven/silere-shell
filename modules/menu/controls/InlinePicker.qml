import QtQuick
import "../../../config"

Column {
    id: root

    property bool open: false
    property Component content: null
    // a twin declared just above the row: with the bar below, the card grows upward, so it opens there
    property Item mirror: null
    readonly property bool above: root.mirror !== null
    readonly property bool _barBelow: Metrics.barAtBottom
    readonly property bool shown: root.above ? root._barBelow && root.mirror.open
        : !root._barBelow && root.open
    readonly property Component _content: root.above ? root.mirror.content : root.content

    width: parent ? parent.width : 0
    spacing: 0

    ScrollHold {
        id: _hold
        watched: root
    }
    // the twin keeps the row declared just after it still
    Component.onCompleted: {
        if (!root.above || !root.parent) return
        const siblings = root.parent.children
        for (let i = 0; i < siblings.length - 1; i++)
            if (siblings[i] === root) { _hold.item = siblings[i + 1]; break }
    }
    onShownChanged: if (root.above) _hold.arm()

    CollapsibleSection {
        id: _section
        width: root.width
        expanded: root.shown

        Loader {
            width: parent.width
            // the section animates to 0, not this Loader's parent - the content column never shrinks
            active: root.shown || _section.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: root._content
        }
    }
}
