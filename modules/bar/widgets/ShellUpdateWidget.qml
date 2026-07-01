import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// Pending shell self-update. Hidden until a check, install, or pending update is
// active. Click checks or applies (pull + restart).
Pill {
    id: root

    readonly property bool show: ShellSettings.barShowShellUpdate
        && (ShellUpdate.pending || ShellUpdate.checking || ShellUpdate.applying)

    visible: opacity > 0.01
    opacity: show ? 1.0 : 0.0
    scale:   show ? 1.0 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }

    glyph:          "󰚰"
    glyphPixelSize: Settings.fontSize + 1
    glyphColor:     Theme.accent
    text:           expanded ? ShellUpdate.statusText : ""
    textColor:      Theme.text
    interactive:    show && !ShellUpdate.checking && !ShellUpdate.applying
    accessibleName: `Shell update, ${ShellUpdate.statusText}`
    accessibleDescription: "Activate to check for or apply the shell update."
    animateGlyph:   false
    shrinkDelay:    0

    contentScanEnabled: (ShellUpdate.applying || ShellUpdate.checking) && !ShellSettings.reduceMotion
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: (ShellUpdate.applying || ShellUpdate.checking) && !ShellSettings.reduceMotion && !Idle.isIdle
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        PauseAnimation  { duration: 300 }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: root.interactive }

    pressed: _tap.pressed
    onActivated: ShellUpdate.pending ? ShellUpdate.apply() : ShellUpdate.check()
    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
