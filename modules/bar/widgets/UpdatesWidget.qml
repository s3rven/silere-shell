import QtQuick
import "../../../services"

StatusActionPill {
    property var screen: null   // ShellScreen this bar sits on, for menu placement

    // visible while a count exists or a check runs, so enabling it gives immediate feedback instead of nothing until the slow first check returns
    show: Updates.available || Updates.isChecking
    busy: Updates.isChecking

    glyph: Updates.icon
    // no number during the first check — icon + sweep, not a misleading "0"; count lands when the query returns.
    // "stale" = a count held over from before a failed check.
    text: expanded ? (Updates.lastFailed ? Updates.statusText + " · " + Updates.lastError : Updates.statusText)
        : Updates.count > 0 ? String(Updates.count) : ""
    accessibleName: Updates.lastFailed ? `Updates check failed, ${Updates.lastError}`
        : Updates.isChecking ? "Checking for updates"
        : Updates.count > 0 ? `${Updates.count} updates available`
        : "System is up to date"
    accessibleDescription: "Activate to check for updates."

    onActivated: Updates.refresh()
}
