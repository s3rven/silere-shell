import QtQuick
import "../../../services"

StatusActionPill {
    id: root

    property var screen: null

    show: ShellSettings.barShowShellUpdate
        && (ShellUpdate.pending || ShellUpdate.checking || ShellUpdate.applying)
    busy: ShellUpdate.checking || ShellUpdate.applying

    glyph: "󰚰"
    accessibleName: ShellUpdate.statusText.length > 0
        ? "Silere update, " + ShellUpdate.statusText : "Silere update"
    text:  expanded ? ShellUpdate.statusText : ""

    onActivated: {
        const point = root.mapToItem(null, root.width / 2, 0)
        MenuState.anchorX = isFinite(point.x) ? point.x : 10
        MenuState.anchorSource = root
        MenuState.triggerScreen = root.screen
        MenuState.setSettingsSection("updates")
        MenuState.showTab(MenuState.settingsTab)
    }
}
