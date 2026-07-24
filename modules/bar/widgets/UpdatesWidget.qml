import QtQuick
import "../../../services"

StatusActionPill {
    property var screen: null

    show: Updates.available || Updates.isChecking
    busy: Updates.isChecking

    glyph: Updates.icon
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""
    accessibleName: Updates.lastFailed ? `Updates check failed, ${Updates.lastError}`
        : Updates.isChecking ? "Checking for updates"
        : Updates.count > 0 ? `${Updates.count} updates available`
        : "System is up to date"
    accessibleDescription: "Activate to check for updates."

    onActivated: Updates.refresh()
}
