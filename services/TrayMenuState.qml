pragma Singleton

import QtQuick

AnchoredPopupState {
    id: root

    readonly property bool armed: true
    property QtObject sourceItem: null
    property bool barBottom: false
    // QtObject (not var) so the reference auto-nulls when the SNI item dies with the menu open
    property QtObject menuHandle: null

    onMenuHandleChanged: if (open && menuHandle === null) close()
    onSourceItemChanged: if (open && sourceItem === null) close()
    // every close path lands here, so the menu-specific handles clear without overriding close()
    onOpenChanged: if (!open) {
        sourceItem = null
        menuHandle = null
    }

    Connections {
        target: ShellSettings
        function onTrayWidgetChanged() { if (!ShellSettings.trayWidget) root.close() }
        function onTrayHiddenChanged() {
            if (root.sourceItem && ShellSettings.trayItemHidden(root.sourceItem.id))
                root.close()
        }
    }

    function branchHovered(branch, flyouts): bool {
        for (let i = 0; i < flyouts.length; i++) {
            const child = flyouts[i]
            if (!child || child.opened !== true || !child.hovered) continue
            let current = child
            for (let depth = 0; current && current.opened === true && depth < 9; depth++) {
                if (current === branch) return true
                current = current.parentFlyout
            }
        }
        return false
    }

    function toggleAt(x: real, screen, handle, bottom: bool, anchor, source): void {
        if (root.open && root.sourceItem === source) {
            root.close()
            return
        }
        // close first: a menu-less item is a valid destination, and the old app's menu must not linger
        if (root.open) root.close()
        sourceItem = source ?? null
        barBottom = bottom
        menuHandle = handle
        openAt(x, screen, anchor)
    }
}
