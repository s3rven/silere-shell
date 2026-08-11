import QtQuick
import "../../../services"

StatusActionPill {
    property var screen: null

    show: ShellSettings.barShowShellUpdate
        && (ShellUpdate.pending || ShellUpdate.checking || ShellUpdate.applying)
    busy: ShellUpdate.checking || ShellUpdate.applying

    glyph: "󰚰"
    text:  expanded ? ShellUpdate.statusText : ""
    accessibleName: `Shell update, ${ShellUpdate.statusText}`
    accessibleDescription: ShellUpdate.pending
        ? "Activate to review the signed shell release."
        : "Activate to check for a signed shell release."

    onActivated: {
        if (!ShellUpdate.pending) {
            ShellUpdate.check()
            return
        }
        const point = root.mapToItem(null, root.width / 2, 0)
        MenuState.anchorX = isFinite(point.x) ? point.x : 10
        MenuState.anchorSource = root
        MenuState.triggerScreen = root.screen
        MenuState.setSettingsSection("updates")
        MenuState.showTab(MenuState.settingsTab)
    }
}
