import QtQuick
import "../../../services"

StatusActionPill {
    id: root

    property var screen: null

    show: ShellSettings.barShowShellUpdate
        && (ShellUpdate.pending || ShellUpdate.checking || ShellUpdate.applying)
    busy: ShellUpdate.checking || ShellUpdate.applying
    interactive: show

    glyph: "󰚰"
    accessibleName: ShellUpdate.statusText.length > 0
        ? "Silere update, " + ShellUpdate.statusText : "Silere update"
    text:  expanded ? ShellUpdate.statusText : ""

    onActivated: if (root.canActivate) MenuState.showSettingsAt("updates", root, root.screen)
}
