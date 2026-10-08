pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Each event owns its envelope, so overlapping flashes never animate the same
// property. The renderer chooses the position and combines their brightness.
SequentialAnimation {
    id: root

    property real glow: 0
    property real spread: 0.28
    property real bloom: 0
    property real peak: 0.40
    property real gatherSpread: 0.02
    property real bloomPeak: 0.30
    property int riseMs: 120
    property int expandMs: 380
    property int holdMs: 220
    property int fadeMs: 1200
    property int spreadFallMs: 800
    property int bloomFallMs: 900
    property int _gatherMs: 0

    function play(gatherMs: int): void {
        root._gatherMs = gatherMs
        root.restart()
    }

    function settleGeometry(): void {
        root.stop()
        root.spread = 0.28
        root.bloom = 0
    }

    function reset(): void {
        root.settleGeometry()
        root.glow = 0
    }

    NumberAnimation {
        target: root; property: "spread"; to: root.gatherSpread
        duration: root._gatherMs; easing.type: Easing.InOutQuad
    }
    ParallelAnimation {
        NumberAnimation { target: root; property: "glow"; to: root.peak; duration: Motion.ms(root.riseMs); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "spread"; to: 0.34; duration: Motion.ms(root.expandMs); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "bloom"; to: root.bloomPeak; duration: Motion.ms(root.riseMs); easing.type: Easing.OutCubic }
    }
    PauseAnimation { duration: Motion.ms(root.holdMs) }
    ParallelAnimation {
        NumberAnimation { target: root; property: "glow"; to: 0; duration: Motion.ms(root.fadeMs); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "spread"; to: 0.28; duration: Motion.ms(root.spreadFallMs); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "bloom"; to: 0; duration: Motion.ms(root.bloomFallMs); easing.type: Easing.OutCubic }
    }
}
