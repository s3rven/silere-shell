import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:     ""
    property bool   available: false
    readonly property bool interactive: root.enabled && root.available

    signal triggered()

    implicitWidth: 32
    implicitHeight: 44
    width: implicitWidth
    height: implicitHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    opacity: root.interactive ? 1.0 : 0.25
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    HoverHandler { id: _hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: _tap
        enabled: root.interactive
        onTapped: {
            root.triggered()
        }
    }

    scale: _tap.pressed ? 0.90
        : _hover.hovered ? Motion.hoverScale : 1.0
    transformOrigin: Item.Center
    MotionBehavior on scale {
        NumberAnimation {
            duration: _tap.pressed ? Motion.press
                : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: _fill
        anchors.centerIn: parent
        width: 34; height: 34; radius: Theme.radiusControl
        antialiasing: true
        color: _tap.pressed
            ? Theme.withAlpha(Theme.accent, 0.13)
            : _hover.hovered
                ? Theme.withAlpha(
                    Theme.mix(Theme.text, Theme.accent, 0.24), 0.075)
                : Theme.withAlpha(Theme.text, 0.05)
        opacity: (_hover.hovered || _tap.pressed) ? 1.0 : 0.0

        OutlineBorder {
            radius: _fill.radius
            outlineWidth: 1
            outlineColor: _hover.hovered
                    ? Theme.withAlpha(Theme.accent, 0.22)
                    : "transparent"
            ColorFade on outlineColor {}
        }

        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }
        ColorFade on color {}
    }
    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: _hover.hovered ? Theme.withAlpha(Theme.text, 0.85) : Theme.withAlpha(Theme.text, 0.45)
        font.pixelSize: Settings.fontSize + 8
        ColorFade on color {}
    }
}
