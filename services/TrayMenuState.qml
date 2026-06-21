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
    property var  menuHandle: null

    function openAt(x: real, screen, handle, bottom: bool): void {
        anchorX = x
        barBottom = bottom
        if (screen) triggerScreen = screen
        menuHandle = handle
        open = true
    }
    function close(): void {
        if (open) open = false
        triggerScreen = null
        menuHandle = null
    }
}
