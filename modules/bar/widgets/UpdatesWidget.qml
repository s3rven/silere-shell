import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    // Visible while a count exists OR a check is running, so enabling it gives
    // immediate feedback instead of nothing until the (slow) first check returns.
    readonly property bool _show: Updates.available || Updates.isChecking

    visible: opacity > 0.01
    opacity: _show ? 1.0 : 0.0
    scale:   _show ? 1.0 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 6; damping: 0.6; epsilon: 0.01 } }

    glyph:          Updates.icon
    glyphPixelSize: Settings.fontSize + 1   // pacman ghost runs optically large
    glyphColor:     Theme.accent
    // No number yet while the first check runs, show just the icon + sweep instead
    // of a misleading "0"; the count lands as soon as the query returns.
    // "stale" flags a count held over from before a failed check.
    text:           hoverActive ? (Updates.lastFailed ? Updates.label + " · stale" : Updates.label)
                  : Updates.count > 0 ? String(Updates.count) : ""
    textColor:      Theme.text
    cursorShape:    Qt.PointingHandCursor
    animateGlyph:   false
    shrinkDelay:    0

    contentScanEnabled: Updates.isChecking && !ShellSettings.reduceMotion
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: Updates.isChecking && !ShellSettings.reduceMotion
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        PauseAnimation  { duration: 300 }
    }

    pressed: _tap.pressed
    TapHandler {
        id: _tap
        acceptedButtons: Qt.LeftButton
        onTapped: Updates.refresh()
    }
}
