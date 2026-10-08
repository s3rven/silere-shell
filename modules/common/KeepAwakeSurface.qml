import QtQuick
import Quickshell
import Quickshell.Wayland

// its own pixel, not the bar: bars can be off per screen and are rebuilt when they move
PanelWindow {
    id: win

    color:         "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "silere-keepawake"
    // A background surface is covered by the wallpaper. Its delayed frame
    // callbacks can stall Qt's other windows while their animations run.
    // Keep this transparent, input-free pixel above them so it stays paced.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    mask: Region {}
    BackgroundEffect.blurRegion: Region { item: null }

    // hyprland weighs an inhibitor only when it is created and a layer that has not mapped yet counts as hidden, so create it after the first frame
    property bool _mapped: false
    Timer {
        interval: 500
        running: win.backingWindowVisible
        onTriggered: win._mapped = true
    }

    IdleInhibitor {
        window: win
        enabled: win._mapped
    }
}
