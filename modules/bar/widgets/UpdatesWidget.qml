import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null   // ShellScreen this bar sits on, for menu placement

    // Visible while a count exists OR a check is running, so enabling it gives
    // immediate feedback instead of nothing until the (slow) first check returns.
    readonly property bool show: Updates.available || Updates.isChecking
    readonly property bool _show: show

    visible: opacity > 0.01
    opacity: _show ? 1.0 : 0.0
    scale:   _show ? 1.0 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }

    glyph:          Updates.icon
    glyphPixelSize: Settings.fontSize + 1   // pacman ghost runs optically large
    glyphColor:     Theme.accent
    // No number yet while the first check runs, show just the icon + sweep instead
    // of a misleading "0"; the count lands as soon as the query returns.
    // "stale" flags a count held over from before a failed check.
    text:           expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
                  : Updates.count > 0 ? String(Updates.count) : ""
    textColor:      Theme.text
    interactive:    _show && !Updates.isChecking
    accessibleName: Updates.lastFailed ? `Updates check failed, ${Updates.lastError}`
        : Updates.isChecking ? "Checking for updates"
        : Updates.count > 0 ? `${Updates.count} updates available`
        : "System is up to date"
    accessibleDescription: "Activate to check for updates."
    animateGlyph:   false
    shrinkDelay:    0

    contentScanEnabled: Updates.isChecking && !ShellSettings.reduceMotion
    contentScanColor:   Theme.withAlpha(Theme.accent, 0.35)
    contentScanWidth:   20

    SequentialAnimation {
        running: Updates.isChecking && !ShellSettings.reduceMotion && !Idle.isIdle
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root.contentScanProgress = 0
        NumberAnimation { target: root; property: "contentScanProgress"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        PauseAnimation  { duration: 300 }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: root.interactive }

    pressed: _tap.pressed
    onActivated: Updates.refresh()
    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
