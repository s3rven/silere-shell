import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property int index: -1
    property int rowHeight: 28
    property bool shown: true
    // the owner maps these slots to rows, so a relayout under the selection never leaves it behind
    readonly property real slot: _slotGlide.value
    property real rowTop: 0

    property real _slotTarget: Math.max(0, root.index)
    onIndexChanged: if (root.index >= 0) root._slotTarget = root.index
    SmoothGlide {
        id: _slotGlide
        target: root._slotTarget
        precision: 0.001
        gate: root.shown
    }

    y: root.rowTop
    height: root.rowHeight
    // the nav sits 6px into the rail, half a device pixel off at 1.25, which softens both side edges of the outline
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    transform: PixelSnap { item: root; dpr: root._dpr }
    opacity: root.shown && root.index >= 0 ? 1 : 0
    visible: opacity > 0.01
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }

    Rectangle {
        width: Metrics.devicePx(root.width, root._dpr)
        height: Metrics.devicePx(root.height, root._dpr)
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
