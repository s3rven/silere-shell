import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property int index: -1
    property int rowHeight: 28
    property bool shown: true
    // the owner maps these slots to rows, so a relayout under the selection never leaves it behind
    readonly property real slot: root._slot
    property real rowTop: 0

    property real _slot: Math.max(0, root.index)
    onIndexChanged: {
        if (root.index < 0) return
        root._slot = root.index
    }
    MotionBehavior on _slot {
        gate: root.shown
        SpringAnimation { spring: 4.4; damping: 0.62; epsilon: 0.002 }
    }

    y: root.rowTop
    height: root.rowHeight
    opacity: root.shown && root.index >= 0 ? 1 : 0
    visible: opacity > 0.01
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusInline
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, ShellSettings.highContrast ? 0.18 : 0.095)

        OutlineBorder {
            radius: parent.radius
            outlineColor: Theme.controlLineActive(Theme.accent)
            ColorFade on outlineColor {}
        }
    }
}
