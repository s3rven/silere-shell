pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property bool barBottom: false
    property ShellScreen triggerScreen: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }
    onAnchorSourceChanged: if (open && anchorSource === null) close()

    function toggleAt(x: real, screen, bottom: bool, source): void {
        if (open) { close(); return }
        anchorX = x
        anchorSource = source ?? null
        barBottom = bottom
        triggerScreen = screen ?? null
        open = true
    }
    function close(): void {
        if (open) open = false
        anchorSource = null
        triggerScreen = null
    }
}
