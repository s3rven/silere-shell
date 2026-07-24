import QtQuick
import "../../../services"

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
