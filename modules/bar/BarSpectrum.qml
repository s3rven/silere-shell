pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "widgets"

Item {
    id: root

    property var  screen: null
    property real inset: 0
    // event glows own the line while they run; the spectrum steps back instead of stacking under them
    property real duck: 0

    anchors.left:        parent.left
    anchors.right:       parent.right
    anchors.bottom:      parent.bottom
    anchors.leftMargin:  inset
    anchors.rightMargin: inset
    height: Math.max(10, Math.min(20, Math.round((parent ? parent.height : 0) * 0.32)))

    readonly property bool wanted: ShellSettings.mediaVisualizerPosition === "underline"
        && ShellSettings.mediaProgress && !ShellSettings.reduceMotion && !Idle.isQuiet
        && Media.shown && Media.playing && Media.cavaReady
        && Monitors.isActive(root.screen)

    opacity: root.wanted ? 1.0 : 0.0
    visible: opacity > 0.001
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic }
    }

    Loader {
        anchors.fill: parent
        // unloading in the same frame the opacity drops leaves the fade animating an empty Loader
        active: root.wanted || _hold.running
        Timer { id: _hold; interval: Motion.slow + 60 }
        // the duck source is already animated; a second Behavior here would trail it
        opacity: Math.max(0, 1.0 - root.duck)
        sourceComponent: Component {
            MediaVisualizer {
                screen: root.screen
                presentationActive: root.wanted
                holdFrame: true
                // a hairline across the whole bar dissolves into the track ends rather than stopping at them
                edgeFadeMax: 140
                // the widget's 7px cap leaves 16 toothpicks stranded in a full-bar slot
                barWidthMax: 22
                lowPower: root.width < 520
            }
        }
    }

    onWantedChanged: if (root.wanted) _hold.stop(); else _hold.restart()
}
