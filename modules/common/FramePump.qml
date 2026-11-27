import QtQuick
import Quickshell
import Quickshell.Wayland

// drawn for a moment as a fullscreen window covers the bar: qt's elapsed-time driver advances only on drawn frames,
// and a fade caught in flight under the cover would otherwise stop every Timer until something of the shell draws
PanelWindow {

    required property ShellScreen targetScreen
    screen: targetScreen

    color:         "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "silere-framepump"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    mask: Region {}
    BackgroundEffect.blurRegion: Region { item: null }
}
