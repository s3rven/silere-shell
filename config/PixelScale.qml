import QtQuick

Scale {
    id: root

    required property Item item
    property real factor: 1
    // QsWindow resolves only on an Item, so the scaled item passes its window's ratio in
    property real dpr: 1
    property real hoverFactor: Motion.hoverScale
    property bool animate: true

    origin.x: root.item.width / 2
    origin.y: root.item.height / 2
    xScale: Metrics.pixelScale(root.item.width, root.factor, root.dpr)
    yScale: Metrics.pixelScale(root.item.height, root.factor, root.dpr)

    // a hover under a device pixel rounds to 1, and releasing onto it is still a hover
    function _timing(to: real, size: real): int {
        if (Math.abs(to - Metrics.pixelScale(size, root.hoverFactor, root.dpr)) < 1e-6) return Motion.hoverIn
        return Math.abs(to - 1) < 1e-6 ? Motion.hoverOut : Motion.press
    }

    MotionBehavior on xScale {
        id: _xMotion
        gate: root.animate
        NumberAnimation { duration: root._timing(_xMotion.targetValue, root.item.width); easing.type: Easing.OutCubic }
    }
    MotionBehavior on yScale {
        id: _yMotion
        gate: root.animate
        NumberAnimation { duration: root._timing(_yMotion.targetValue, root.item.height); easing.type: Easing.OutCubic }
    }
}
