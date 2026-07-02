pragma Singleton

import QtQuick
import Quickshell

// mirrors CalendarState
Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property bool barBottom: false
    property var  triggerScreen: null

    function toggleAt(x: real, screen, bottom: bool): void {
        if (open) { close(); return }
        anchorX = x
        barBottom = bottom
        if (screen) triggerScreen = screen
        open = true
    }
    function close(): void {
        if (open) open = false
        triggerScreen = null
    }
}
