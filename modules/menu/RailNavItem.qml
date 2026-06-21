import QtQuick
import "../../config"
import "../../services"

// Shared by MenuWindow's nav rail and its power button: icon, accent bar,
// press-squish, and a hover-revealed label pill. Extra children (e.g. a
// notification badge) can be nested directly inside an instance.
Item {
    id: root

    property string glyph: ""
    property string label: ""
    property bool active: false
    property color accentColor: Theme.accent
    property int railW: 48

    signal tapped()

    width: railW
    height: 38

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }
    TapHandler   { id: _tap; onTapped: root.tapped() }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 22
        radius: 1.5
        color: root.accentColor
        opacity: root.active ? 1.0 : 0.0
        scale:   root.active ? 1.0 : 0.4
        transformOrigin: Item.Left
        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        // Hover previews the same hue the active state commits to, instead of
        // jumping straight from neutral subtext to a fully different color.
        color: root.active
            ? root.accentColor
            : Theme.withAlpha(Theme.mix(Theme.subtext, root.accentColor, _hover.hovered ? 0.30 : 0),
                               _hover.hovered ? 0.8 : 0.5)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize + 4
        renderType: Text.NativeRendering
        scale: _tap.pressed ? 0.86 : (root.active ? 1.05 : 1.0)
        transformOrigin: Item.Center
        Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation  { duration: Motion.fast } }
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 0.4 } }
    }

    // Hover pill, label to the right of the icon. Reveals at the normal pace
    // but hides quickly so it doesn't linger over content the user has
    // already moved on to.
    Rectangle {
        id: _pill
        readonly property bool _show: _hover.hovered && !root.active

        x: root.railW + 4
        anchors.verticalCenter: parent.verticalCenter
        width: _pillLabel.implicitWidth + 16
        height: 22; radius: 11
        color: Theme.withAlpha(Theme.surface, 0.99)
        border.width: 1; border.color: Theme.withAlpha(Theme.subtext, 0.14)
        antialiasing: true
        opacity: _show ? 1.0 : 0.0
        scale:   _show ? 1.0 : 0.85
        visible: opacity > 0.01
        transformOrigin: Item.Left
        z: 10
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        Text {
            id: _pillLabel
            anchors.centerIn: parent
            text: root.label
            color: Theme.withAlpha(Theme.subtext, 0.85)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
        }
    }
}
