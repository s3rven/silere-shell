import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root
    property var screen: null
    readonly property bool show: ShellSettings.barShowKeyboard && InputState.available
    readonly property bool layoutVisible: show || opacity > 0.001
    collapsed: !show
    visible: layoutVisible
    opacity: show ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
    glyph: InputState.capsLock ? "󰘲" : "󰌌"
    glyphColor: InputState.capsLock ? Theme.barWarning : Theme.barSubtext
    text: [root.expanded ? InputState.layout : InputState.shortLayout, InputState.capsLock ? "CAPS" : ""]
        .filter(part => part.length > 0).join(" ")
    // the hover shows the full layout name, as long as the other widgets' details get
    maxTextWidth: compact ? 150 : 260
    accessibleName: ["Keyboard", InputState.layout,
        InputState.capsAvailable ? (InputState.capsLock ? "Caps Lock on" : "Caps Lock off") : ""]
        .filter(part => part.length > 0).join(", ")
    interactive: root.show && InputState.layout.length > 0
    onActivated: if (root.canActivate) Compositor.cycleKeyboardLayout()
    pressed: _tap.pressed
    TapHandler { id: _tap; enabled: root.canActivate; onTapped: root.activated() }
}
