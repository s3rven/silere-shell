pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property QtObject sourceItem: null
    property bool barBottom: false
    property ShellScreen triggerScreen: null
    // QtObject (not var) so the reference auto-nulls when the SNI item dies with the menu open
    property QtObject menuHandle: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }

    onMenuHandleChanged: if (open && menuHandle === null) close()
    onAnchorSourceChanged: if (open && anchorSource === null) close()

    Connections {
        target: ShellSettings
        function onTrayWidgetChanged() { if (!ShellSettings.trayWidget) root.close() }
    }

    function toggleAt(x: real, screen, handle, bottom: bool, anchor, source): void {
        if (root.open && root.sourceItem === source) {
            root.close()
            return
        }
        anchorX = x
        anchorSource = anchor ?? null
        sourceItem = source ?? null
        barBottom = bottom
        triggerScreen = screen ?? null
        menuHandle = handle
        open = true
    }
    function close(): void {
        if (open) open = false
        triggerScreen = null
        anchorSource = null
        sourceItem = null
        menuHandle = null
    }
}
