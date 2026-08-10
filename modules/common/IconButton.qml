pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    property string glyph: ""
    property string accessibleName: "Action"
    property color accentColor: Theme.accent
    property int buttonSize: Metrics.rowHeightFor(28)
    property int glyphPixelSize: Settings.fontSize + 2

    signal triggered()

    readonly property bool pressed: _tap.pressed || _keys.pressed

    FocusVisual { id: _focusVisual; target: root }
    KeyActivation {
        id: _keys
        enabled: root.enabled
        focusVisual: _focusVisual
        onActivated: root.activate()
    }

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1.0 : 0.38
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
    activeFocusOnTab: enabled || activeFocus

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    onActiveFocusChanged: if (!activeFocus) _keys.cancel()
    onEnabledChanged: if (!enabled) _keys.cancel()

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.enabled
    Accessible.pressed: root.pressed
    Accessible.onPressAction: root.activate()

    Keys.onPressed:  event => _keys.press(event)
    Keys.onReleased: event => _keys.release(event)

    HoverHandler {
        id: _hover
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: {
            _focusVisual.takePointerFocus()
            root.activate()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        color: root.pressed
            ? Theme.withAlpha(root.accentColor, 0.20)
            : _focusVisual.active
                ? Theme.withAlpha(root.accentColor, 0.13)
                : _hover.hovered
                    ? Theme.withAlpha(Theme.subtext, 0.12)
                    : "transparent"

        OutlineBorder {
            radius: width / 2
            outlineWidth: _focusVisual.active ? 2 : 1
            outlineColor: _focusVisual.active ? Theme.withAlpha(root.accentColor, Theme.focusRingAlpha) : "transparent"
        }

        ColorFade on color {}
    }

    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: _focusVisual.active || _hover.hovered || root.pressed
            ? Theme.text : Theme.withAlpha(Theme.subtext, 0.72)
        font.pixelSize: root.glyphPixelSize
        scale: root.pressed ? 0.90 : 1.0
        transformOrigin: Item.Center

        ColorFade on color {}
        MotionBehavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }
}
