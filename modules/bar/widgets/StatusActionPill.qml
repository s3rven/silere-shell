import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property bool show: false
    property bool busy: false
    readonly property bool layoutVisible: show || opacity > 0.01

    visible: layoutVisible
    collapsed: !show
    opacity: show ? 1.0 : 0.0
    scale:   show ? 1.0 : 0.7
    transformOrigin: Item.Center
    MotionBehavior on opacity {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    MotionBehavior on scale   {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }

    glyphPixelSize: Settings.iconSize + 1
    glyphColor:     Theme.accent
    textColor:      Theme.text
    interactive:    show && !busy
    animateGlyph:   false
    shrinkDelay:    0

    // an update check or apply outlasts the quiet stage, and this loop is per-frame work
    readonly property bool _scanning: root.busy && !Idle.isQuiet
    contentScanEnabled: root._scanning
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: root._scanning && root.motionActive
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: Motion.ms(900); easing.type: Easing.InOutSine }
        PauseAnimation  { duration: Motion.ms(300) }
    }

    pressed: _tap.pressed
    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
