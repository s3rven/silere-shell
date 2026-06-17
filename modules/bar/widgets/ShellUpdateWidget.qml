import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// Pending shell self-update. Hidden entirely until the flag file exists, so it
// costs nothing in the common case. Left-click applies (pull + restart);
// right-click opens the menu like the other status pills.
Pill {
    id: root

    property var screen: null

    readonly property bool _show: ShellUpdate.pending

    visible: opacity > 0.01
    opacity: _show ? 1.0 : 0.0
    scale:   _show ? 1.0 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 6; damping: 0.6; epsilon: 0.01 } }

    glyph:          "󰚰"
    glyphPixelSize: Settings.fontSize + 1
    glyphColor:     Theme.accent
    text:           hoverActive ? (ShellUpdate.applying ? "updating…" : ShellUpdate.label) : ""
    textColor:      Theme.text
    cursorShape:    Qt.PointingHandCursor
    animateGlyph:   false
    shrinkDelay:    0

    contentScanEnabled: ShellUpdate.applying && !ShellSettings.reduceMotion
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: ShellUpdate.applying && !ShellSettings.reduceMotion
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        PauseAnimation  { duration: 300 }
    }

    pressed: _tap.pressed
    TapHandler {
        id: _tap
        acceptedButtons: Qt.LeftButton
        onTapped: ShellUpdate.apply()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: MenuState.toggleAt(root.mapToItem(null, root.width / 2, 0).x, root.screen)
    }
}
