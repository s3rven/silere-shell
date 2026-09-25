import QtQuick

Scale {
    id: root

    required property Item item
    property real factor: 1
    // QsWindow resolves only on an Item, so the scaled item passes its window's ratio in
    property real dpr: 1
    property int duration: Motion.fast
    property bool animate: true

    origin.x: root.item.width / 2
    origin.y: root.item.height / 2
    xScale: Metrics.pixelScale(root.item.width, root.factor, root.dpr)
    yScale: Metrics.pixelScale(root.item.height, root.factor, root.dpr)

    MotionBehavior on xScale {
        gate: root.animate
        NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic }
    }
    MotionBehavior on yScale {
        gate: root.animate
        NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic }
    }
}
