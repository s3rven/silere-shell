pragma Singleton

import QtQuick
import Quickshell

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

    // an app that autostarts before the tray's watcher exists registers into nothing and never retries; one pass
    // once the watcher is up adopts those items, as KDE's own watcher does. Later apps find it and register themselves
    property bool _orphanScanDone: false
    function recoverOrphanItems(): void {
        if (root._orphanScanDone || Quickshell.env("SILERE_SANDBOX") === "1") return
        root._orphanScanDone = true
        _orphanDelay.restart()
    }
    property Timer _orphanDelay: Timer {
        id: _orphanDelay
        interval: 1500
        onTriggered: _orphanScan.running = true
    }
    property BoundedProcess _orphanScan: BoundedProcess {
        id: _orphanScan
        timeoutMs: 10000
        environment: ({ "LC_ALL": "C" })
        command: ["sh", "-c",
            'command -v busctl >/dev/null 2>&1 || exit 0; w=org.kde.StatusNotifierWatcher; '
            + 'reg=$(busctl --user get-property $w /StatusNotifierWatcher $w RegisteredStatusNotifierItems 2>/dev/null '
            + '| tr " " "\\n" | tr -d "\\042" | sed "s|/.*||") || exit 0; '
            + 'busctl --user list --no-legend --acquired 2>/dev/null | while read -r name rest; do '
            + 'case $name in org.kde.StatusNotifierItem-*) ;; *) continue ;; esac; '
            + 'printf "%s\\n" "$reg" | grep -qxF "$name" && continue; '
            + 'busctl --user call $w /StatusNotifierWatcher $w RegisterStatusNotifierItem s "$name" >/dev/null 2>&1; '
            + 'done']
    }

    // a diagonal move toward an open submenu crosses its siblings; only a pause there switches branches
    function siblingFlyoutOpen(siblings, self): bool {
        for (let i = 0; i < siblings.length; i++) {
            const c = siblings[i]
            if (c && c !== self && c.flyoutOpen === true) return true
        }
        return false
    }

    // quickshell drops hidden entries but keeps their separators: no rule leads, trails or doubles another
    function strayRule(rows, index: int): bool {
        if (index <= 0 || (rows[index - 1]?.isSeparator ?? false)) return true
        for (let i = index + 1; i < rows.length; i++)
            if (!(rows[i]?.isSeparator ?? false)) return false
        return true
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
