pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Follows focus unless the user pins a monitor.
    readonly property ShellScreen overlayScreen: {
        const screens = Quickshell.screens
        if (!screens || screens.length === 0) return null

        const pin = ShellSettings.overlayMonitor
        if (pin && pin.length > 0) {
            for (let i = 0; i < screens.length; i++)
                if (screens[i].name === pin) return screens[i]
        }

        const focused = Compositor.focusedMonitor
        if (focused && focused.length > 0) {
            for (let i = 0; i < screens.length; i++)
                if (screens[i].name === focused) return screens[i]
        }
        return screens[0]
    }

    readonly property string activeName: overlayScreen ? overlayScreen.name : ""

    // Disabled screens stored comma-joined; absent = bar on.
    function barEnabled(screen): bool {
        if (!screen) return false
        const off = ShellSettings.barDisabledMonitors
        if (!off || off.length === 0) return true
        return ("," + off + ",").indexOf("," + screen.name + ",") < 0
    }

    // integrated overlays render on one bar; prefer the floating-overlay screen, fall back to a live bar if its bar is disabled
    readonly property ShellScreen overlayBarScreen: {
        const preferred = overlayScreen
        if (barEnabled(preferred)) return preferred

        const screens = Quickshell.screens || []
        for (let i = 0; i < screens.length; i++)
            if (barEnabled(screens[i])) return screens[i]
        return null
    }
    readonly property string overlayBarName: overlayBarScreen ? overlayBarScreen.name : ""

    function setBarEnabled(name: string, on: bool): void {
        if (!name || name.length === 0) return
        const parts = (ShellSettings.barDisabledMonitors || "").split(",").filter(s => s.length > 0)
        const idx = parts.indexOf(name)
        if (on) {
            if (idx < 0) return
            parts.splice(idx, 1)
        } else {
            if (idx >= 0) return
            // never turn off the last live bar — the menu opens from it
            const screens = Quickshell.screens || []
            let live = 0
            for (let i = 0; i < screens.length; i++) if (barEnabled(screens[i])) live++
            if (live <= 1) return
            parts.push(name)
        }
        ShellSettings.barDisabledMonitors = parts.join(",")
    }
}
