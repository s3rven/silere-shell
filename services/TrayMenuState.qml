pragma Singleton

import QtQuick

AnchoredPopupState {
    id: root

    property QtObject sourceItem: null
    property bool barBottom: false
    // QtObject (not var) so the reference auto-nulls when the SNI item dies with the menu open
    property QtObject menuHandle: null

    onMenuHandleChanged: if (open && menuHandle === null) close()
    // every close path lands here, so the menu-specific handles clear without overriding close()
    onOpenChanged: if (!open) {
        sourceItem = null
        menuHandle = null
    }

    Connections {
        target: ShellSettings
        function onTrayWidgetChanged() { if (!ShellSettings.trayWidget) root.close() }
    }

    function toggleAt(x: real, screen, handle, bottom: bool, anchor, source): void {
        if (root.open && root.sourceItem === source) {
            root.close()
            return
        }
        sourceItem = source ?? null
        barBottom = bottom
        menuHandle = handle
        openAt(x, screen, anchor)
    }
}
