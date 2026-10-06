import QtQuick
import Quickshell.Hyprland

// apart from the adapter: Quickshell can be built without focus grabbing, and the missing type must cost only this
HyprlandFocusGrab {
    required property var popup

    windows: [popup.cardWindow]
    active: popup.open
    onCleared: popup.dismissed()
}
