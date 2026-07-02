import QtQuick
import "../../../services"

StatusActionPill {
    property var screen: null   // ShellScreen this bar sits on, for menu placement

    // Visible while a count exists OR a check is running, so enabling it gives
    // immediate feedback instead of nothing until the (slow) first check returns.
    show: Updates.available || Updates.isChecking
    busy: Updates.isChecking

    glyph: Updates.icon
    // No number yet while the first check runs, show just the icon + sweep instead
    // of a misleading "0"; the count lands as soon as the query returns.
    // "stale" flags a count held over from before a failed check.
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""
    accessibleName: Updates.lastFailed ? `Updates check failed, ${Updates.lastError}`
        : Updates.isChecking ? "Checking for updates"
        : Updates.count > 0 ? `${Updates.count} updates available`
        : "System is up to date"
    accessibleDescription: "Activate to check for updates."

    onActivated: Updates.refresh()
}
