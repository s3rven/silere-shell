import QtQuick
import Quickshell.Hyprland

// apart from the adapter: Quickshell can be built without focus grabbing, and the missing type must cost only this
HyprlandFocusGrab {
    id: grab
    required property var popup

    // a grab cleared while another popup hands over to this one is that popup's surface leaving the pointer, not a
    // click outside: it is taken again, a few times at most, so a real click still closes it once the handover ends
    property bool _retaking: false
    property int _retakes: 0

    windows: [popup.cardWindow]
    active: popup.open && !grab._retaking
    // so is the click a bar flip lands under the pointer (the second of a double click on Position): the card moved
    // away from it, and without a grab the tap guard swallows that click
    onCleared: {
        if (popup.open && (OverlayCoordinator.handingOver || popup.ignoringTaps === true) && grab._retakes < 3) {
            grab._retakes++
            grab._retaking = true
            Qt.callLater(() => grab._retaking = false)
            return
        }
        popup.dismissed()
    }
    // a grab has no default property for a Connections child, so it watches the popup through a property of its own
    readonly property bool _open: popup.open
    on_OpenChanged: if (!grab._open) grab._retakes = 0
}
