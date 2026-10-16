import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property var _layouts: Compositor.keyboardLayouts
    readonly property var _current: Compositor.keyboardLayoutIndex >= 0 ? _layouts[Compositor.keyboardLayoutIndex] : null
    readonly property bool show: ShellSettings.barShowKeyboardLayout && _layouts.length > 1 && _current !== null
    readonly property bool layoutVisible: show || opacity > 0.001
    readonly property string _name: _current ? String(_current.name || _current.code || "") : ""

    collapsed: !show
    visible:   layoutVisible
    opacity:   show ? 1.0 : 0.0
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    glyph: "󰌌"
    glyphColor: Theme.subtext
    textColor:  Theme.text
    readonly property string _label: Compositor.keyboardLayoutLabel(_current, _layouts)
    text: _label
    interactive: show
    accessibleName: "Keyboard layout, " + (root._name.length > 0 ? root._name : root._label)

    pressed: _tap.pressed
    onActivated: if (root.canActivate) Compositor.nextKeyboardLayout()

    TapHandler {
        id: _tap
        enabled: root.canActivate
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
