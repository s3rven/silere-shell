import QtQuick
import "../../config"
import "../../services"

// gated by a switch that's in view → collapse; dim (+dependsNote/HintText) only when the switch isn't reachable
Item {
    id: root

    property bool expanded: true
    default property alias data: _content.data

    // lets an enclosing SettingsCard recurse through this group when deriving dividers/rounding, so nested rows behave like flat ones
    readonly property bool isRadiusGroup: true
    readonly property Item radiusColumn: _content
    // inherit the divider-transparency of whatever opens the group, so a hint-only section draws no line above its intro text
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
            duration:    root.expanded ? Motion.normal : Motion.fast
            easing.type: Easing.OutCubic
        }
    }

    Column {
        id: _content
        width: parent.width

        y: 0
        opacity: root.expanded ? 1.0 : 0.0
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.OutCubic
            }
        }
    }

    // internal seams between this group's rows (the card only divides its direct children); clipped away with the group when collapsed
    RowDividers { column: _content }
}
