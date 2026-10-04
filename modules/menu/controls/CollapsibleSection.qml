import QtQuick
import "../../../config"

Item {
    id: root

    property bool expanded: true
    // set on both halves of a mode swap so the card height stays monotonic
    property bool symmetric: false
    default property alias rows: _content.data
    // semantic presence changes once per toggle. Divider/corner discovery can depend on this instead of rereading animated height every frame
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

    Disclosure on height { symmetric: root.symmetric }

    Column {
        id: _content
        width: parent.width

        y: 0
        opacity: root.expanded ? 1.0 : 0.0
        // match the height's timing; a symmetric pair shares one curve so its opacities sum to 1
        MotionBehavior on opacity {
            id: _contentFade
            NumberAnimation {
                duration: root.symmetric || _contentFade.targetValue > 0.5
                    ? Motion.medium : Motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.symmetric || _contentFade.targetValue > 0.5
                    ? Motion.emphasizedDecel : Motion.emphasizedAccel
            }
        }
    }

    RowDividers { column: _content }
}
