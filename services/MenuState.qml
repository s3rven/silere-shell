pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool open:    false
    property real anchorX: 10    // screen X of the trigger point; set before calling toggle()
    property var  triggerScreen: null  // ShellScreen the menu was opened from; null → focused

    // Lets pages ask the menu to switch tabs (0 Home, 1 Settings, 2 Recent)
    // without holding a reference to the panel.
    signal tabRequested(int index)

    function toggleAt(x: real, screen): void {
        anchorX = x
        triggerScreen = screen ?? null
        open = !open
        if (!open) triggerScreen = null
        else ShellSettings.hasOpenedMenu = true
    }
    function close():               void { triggerScreen = null; if (open) open = false }
    function showTab(index: int):   void { if (!open) open = true; tabRequested(index) }
}
