import QtQuick
import "../../config"
import "../../services"

// Secondary transport button (previous / next) for the menu's media card. The
// play/pause button stays bespoke in HomePage, its glyph stamps on state change
// and it carries the accent pad that marks the primary action.
Item {
    id: root

    property string glyph:     ""
    property string accessibleName: "Media control"
    // Action availability, drives dimming and makes the button inert when off:
    // no pointer cursor, no hover/press feedback.
    property bool   available: false

    signal triggered()

    width: 32; height: 44
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    opacity: root.available ? 1.0 : 0.25
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    activeFocusOnTab: root.available
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat && root.available) root.triggered(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat && root.available) root.triggered(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat && root.available) root.triggered(); event.accepted = true }

    HoverHandler { id: _hover; enabled: root.available; cursorShape: Qt.PointingHandCursor }
    TapHandler   { id: _tap;   enabled: root.available; onTapped: root.triggered() }

    scale: _tap.pressed ? 0.86 : 1.0; transformOrigin: Item.Center
    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.centerIn: parent
        width: 36; height: 36; radius: 18
        antialiasing: true
        color: Theme.withAlpha(Theme.text, _tap.pressed ? 0.15 : 0.08)
        opacity: (_hover.hovered || _tap.pressed || root.activeFocus) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on color   { ColorAnimation  { duration: Motion.fast } }
    }
    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: _hover.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.5)
        font.family: Settings.font; font.pixelSize: Settings.fontSize + 8
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }
}
