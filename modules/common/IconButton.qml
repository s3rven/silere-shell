pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    property string glyph: ""
    property string accessibleName: ""
    property color accentColor: Theme.accent
    property int buttonSize: Metrics.rowHeightFor(28)
    property int glyphPixelSize: Settings.fontSize + 2

    signal triggered()

    readonly property bool pressed: _tap.pressed

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.enabled
    Accessible.onPressAction: root.activate()

    HoverHandler {
        id: _hover
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: {
            root.activate()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        scale: root.pressed ? Motion.pressScale
            : _hover.hovered ? Motion.hoverScale : 1.0
        transformOrigin: Item.Center
        color: Theme.buttonFill(root.accentColor, _hover.hovered, root.pressed)

        OutlineBorder {
            radius: width / 2
            outlineWidth: 1
            outlineColor: Theme.buttonLine(
                root.accentColor, _hover.hovered, root.pressed)
            ColorFade on outlineColor {}
        }

        ColorFade on color {}
        MotionBehavior on scale {
            NumberAnimation {
                duration: root.pressed ? Motion.press
                    : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
    }

    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: _hover.hovered || root.pressed
            ? Theme.text : Theme.withAlpha(Theme.subtext, 0.72)
        font.pixelSize: root.glyphPixelSize

        ColorFade on color {}
    }
}
