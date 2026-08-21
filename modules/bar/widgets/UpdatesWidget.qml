import QtQuick
import "../../../config"
import "../../../services"

StatusActionPill {
    property var screen: null

    show: Updates.available || Updates.isChecking || Updates.checkBroken
    busy: Updates.isChecking

    glyph: Updates.checkBroken ? "󰀦" : Updates.icon
    accessibleName: Updates.statusText.length > 0
        ? "System updates, " + Updates.statusText : "System updates"
    glyphColor: Updates.checkBroken ? Theme.warning : Theme.accent
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""

    onActivated: Updates.refresh()
}
