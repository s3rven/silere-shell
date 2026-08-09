pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../common"

Rectangle {
    id: root

    required property real rowHeight
    required property bool shown

    anchors.centerIn: parent
    width: parent.width
    height: root.rowHeight
    radius: Metrics.hoverRadiusFor(height)
    antialiasing: true
    color: Theme.withAlpha(Theme.accent, 0.14)
    opacity: root.shown ? 1.0 : 0.0
    visible: opacity > 0.001
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    OutlineBorder {
        radius: root.radius
        outlineColor: Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
    }
}
