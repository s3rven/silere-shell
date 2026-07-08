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
    // QtObject (not var) so the reference auto-nulls when the SNI item dies with the menu open
    property QtObject menuHandle: null

    onMenuHandleChanged: if (open && menuHandle === null) close()

    Connections {
        target: ShellSettings
        function onTrayWidgetChanged() { if (!ShellSettings.trayWidget) root.close() }
    }

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
