pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true

    // one list, so a row reused in another panel does not leave its service keyed to the first
    readonly property bool anyOpen: {
        const list = OverlayCoordinator.popups
        for (let i = 0; i < list.length; i++) {
            if (list[i].controlSurface && list[i].open) return true
        }
        return false
    }

    // what a compositor shortcut opens, named once here instead of in each caller
    function keybindToggle(surface: string): string {
        if (surface === "menu") return MenuState.keybindToggle()
        if (surface === "tray") return TrayMenuState.keybindToggle()
        return "error: no shortcut surface named " + surface
    }
}
