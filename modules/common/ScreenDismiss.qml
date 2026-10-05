import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// hyprland 0.57 and niri hand a click on another monitor to whatever is under it, which left the popup open and holding the keyboard
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-dismiss"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true; bottom: true }
    // an empty region, not none: a catch-all silere layer rule would otherwise blur this whole screen
    BackgroundEffect.blurRegion: Region { item: null }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: OverlayCoordinator.closeAll()
    }
}
