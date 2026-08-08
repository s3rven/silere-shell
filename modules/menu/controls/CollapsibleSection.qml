import QtQuick
import "../../../config"

Item {
    id: root

    property bool expanded: true
    default property alias rows: _content.data
    // Semantic presence changes once per toggle. Divider/corner discovery can
    // depend on this instead of rereading animated height every frame.
    readonly property bool layoutPresent: expanded

    readonly property bool isRadiusGroup: true
    readonly property Item radiusColumn: _content
    readonly property bool suppressDividerAbove: {
        const ch = _content.children
        for (let i = 0; i < ch.length; i++) {
            const c = ch[i]
            if (c && c.visible && c.height > 0.5) return (c.suppressDividerAbove ?? false)
        }
        return false
    }

    width:   parent ? parent.width : 0
    height:  expanded ? _content.implicitHeight : 0
    clip:    true
    enabled: expanded
    visible: expanded || height > 0.5

    Disclosure on height { expanded: root.expanded }

    Column {
        id: _content
        width: parent.width

        y: 0
        opacity: root.expanded ? 1.0 : 0.0
        MotionBehavior on opacity {
            NumberAnimation {
                duration: Motion.fast
                easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic
            }
        }
    }

    RowDividers { column: _content }
}
