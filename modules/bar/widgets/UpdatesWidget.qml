import QtQuick
import "../../../config"
import "../../../services"

StatusActionPill {
    id: root
    property var screen: null

    show: Updates.available || Updates.isChecking || Updates.checkBroken
    busy: Updates.isChecking
    // a running check blocks another refresh, not the package details
    interactive: show

    glyph: Updates.checkBroken ? "󰀦" : Updates.icon
    accessibleName: Updates.statusText.length > 0
        ? "System updates, " + Updates.statusText : "System updates"
    glyphColor: Updates.checkBroken ? Theme.warning : Theme.accent
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""

    onActivated: MenuState.showSettingsAt("updates", root, root.screen)

    TapHandler {
        enabled: root.show && !root.busy
        acceptedButtons: Qt.RightButton
        onTapped: Updates.refresh()
    }
}
