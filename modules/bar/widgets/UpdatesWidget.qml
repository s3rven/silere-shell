import QtQuick
import "../../../services"

StatusActionPill {
    property var screen: null

    show: Updates.available || Updates.isChecking
    busy: Updates.isChecking

    glyph: Updates.icon
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""

    onActivated: Updates.refresh()
}
