import QtQuick
import Quickshell
import Quickshell.Wayland

// its own pixel, not the bar: bars can be off per screen and are rebuilt when they move
PanelWindow {
    id: win

    color:         "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "silere-keepawake"
    WlrLayershell.layer: WlrLayer.Background
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
