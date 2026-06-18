pragma Singleton

import QtQuick
import Quickshell

// Open/anchor state for the bar's calendar popup. Mirrors MenuState, the bar
// clock pokes this, the popup window reads it, so neither holds a reference to
// the other. anchorX is the clock's screen-x, used to pop the card beneath it.
Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property var  triggerScreen: null

    function toggleAt(x: real, screen): void {
        if (open) { close(); return }   // also clears triggerScreen, like close()
        anchorX = x
        if (screen) triggerScreen = screen
        open = true
    }
    function close(): void { if (open) open = false; triggerScreen = null }
}
