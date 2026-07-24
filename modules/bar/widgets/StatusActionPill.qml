import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property bool show: false
    property bool busy: false
    property bool barActive: true

    visible: opacity > 0.01
    opacity: show ? 1.0 : 0.0
    scale:   show ? 1.0 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }

    glyphPixelSize: Settings.iconSize + 1
    glyphColor:     Theme.accent
    textColor:      Theme.text
    interactive:    show && !busy
    animateGlyph:   false
    shrinkDelay:    0

    contentScanEnabled: busy && root.barActive && !ShellSettings.reduceMotion
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: root.busy && root.barActive && !ShellSettings.reduceMotion && !Idle.isIdle
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: Motion.ms(900); easing.type: Easing.InOutSine }
        PauseAnimation  { duration: Motion.ms(300) }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: root.interactive }

    pressed: _tap.pressed
    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
