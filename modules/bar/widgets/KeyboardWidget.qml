import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root
    property var screen: null
    readonly property bool show: ShellSettings.barShowKeyboard && InputState.available
    collapsed: !show
    visible: show || opacity > 0.001
    opacity: show ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
    glyph: InputState.capsLock ? "󰘲" : "󰌌"
    glyphColor: InputState.capsLock ? Theme.warning : Theme.subtext
    text: (root.expanded ? InputState.layout : InputState.shortLayout) + (InputState.capsLock ? " CAPS" : "")
    accessibleName: "Keyboard, " + InputState.layout
        + (InputState.capsAvailable ? (InputState.capsLock ? ", Caps Lock on" : ", Caps Lock off") : "")
    interactive: root.show && InputState.layout.length > 0
    onActivated: if (root.canActivate) Compositor.cycleKeyboardLayout()
    pressed: _tap.pressed
    TapHandler { id: _tap; enabled: root.canActivate; onTapped: root.activated() }
}
