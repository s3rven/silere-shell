pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // every feature that needs to know about fullscreen windows states its demand here,
    // so no one consumer owns another's and silence cannot depend on who loaded first
    readonly property bool wanted: ShellSettings.notifFullscreenSilence
        || ShellSettings.mediaProgress
        || (ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated)

    readonly property bool active: root.wanted && Compositor.activeFullscreen

    // the active toplevel can change while nothing was watching; demand forces a fresh answer
    function refresh(): void { Compositor.refreshToplevels() }

    Component.onCompleted: if (root.wanted) root.refresh()
    onWantedChanged: if (root.wanted) root.refresh()
}
