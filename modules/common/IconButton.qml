pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string accessibleName: "Action"
    property color accentColor: Theme.accent
    property int buttonSize: 28
    property int glyphPixelSize: Settings.fontSize + 2

    signal triggered()

    property bool _keyboardPressed: false
    readonly property bool pressed: _tap.pressed || _keyboardPressed

    width: buttonSize
    height: buttonSize
    opacity: enabled ? 1.0 : 0.38
    activeFocusOnTab: enabled

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    onActiveFocusChanged: if (!activeFocus) _keyboardPressed = false
    onEnabledChanged: if (!enabled) _keyboardPressed = false

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.enabled
    Accessible.onPressAction: root.activate()

    Keys.onPressed: event => {
        if (!root.enabled || event.isAutoRepeat
                || (event.key !== Qt.Key_Space
                    && event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter)) return
        root._keyboardPressed = true
        event.accepted = true
    }
    Keys.onReleased: event => {
        if (!root._keyboardPressed
                || (event.key !== Qt.Key_Space
                    && event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter)) return
        root._keyboardPressed = false
        event.accepted = true
        root.activate()
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: root.activate()
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        color: root.pressed
            ? Theme.withAlpha(root.accentColor, 0.20)
            : root.activeFocus
                ? Theme.withAlpha(root.accentColor, 0.13)
                : _hover.hovered
                    ? Theme.withAlpha(Theme.subtext, 0.12)
                    : "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.withAlpha(root.accentColor, 0.68)

        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.activeFocus || _hover.hovered || root.pressed
            ? Theme.text : Theme.withAlpha(Theme.subtext, 0.72)
        font.family: Settings.font
        font.pixelSize: root.glyphPixelSize
        renderType: Text.NativeRendering
        scale: root.pressed ? 0.90 : 1.0
        transformOrigin: Item.Center

        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }
}
