import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property bool expanded: true
    property int indent: 0
    default property alias data: _content.data

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
    visible: height > 0.5

    Behavior on height {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation {
            duration: root.expanded ? Motion.medium : Motion.fast
            easing.type: root.expanded ? Easing.OutQuart : Easing.InCubic
        }
    }

    Column {
        id: _content
        x: root.indent
        width: Math.max(1, parent.width - root.indent)

        y: 0
        opacity: root.expanded ? 1.0 : 0.0
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration: Motion.fast
                easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic
            }
        }
    }

    RowDividers { column: _content }
}
