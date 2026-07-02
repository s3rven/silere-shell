import QtQuick
import "../../../services"

// Pending shell self-update. Hidden until a check, install, or pending update is
// active. Click checks or applies (pull + restart).
StatusActionPill {
    show: ShellSettings.barShowShellUpdate
        && (ShellUpdate.pending || ShellUpdate.checking || ShellUpdate.applying)
    busy: ShellUpdate.checking || ShellUpdate.applying

    glyph: "󰚰"
    text:  expanded ? ShellUpdate.statusText : ""
    accessibleName: `Shell update, ${ShellUpdate.statusText}`
    accessibleDescription: "Activate to check for or apply the shell update."

    onActivated: ShellUpdate.pending ? ShellUpdate.apply() : ShellUpdate.check()
}
