import QtQuick
import "../../config"
import "../../services"

// secondary transport button (prev/next) for the media card; play/pause stays bespoke in HomePage (stamping glyph + accent pad)
Item {
    id: root

    property string glyph:     ""
    property string accessibleName: "Media control"
    // action availability: drives dimming and makes the button inert (no cursor, no hover/press) when off
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
        width: 34; height: 34; radius: Theme.radiusControl
        antialiasing: true
        color: Theme.withAlpha(Theme.text, _tap.pressed ? 0.15 : 0.08)
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.withAlpha(Theme.accent, 0.6)
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
