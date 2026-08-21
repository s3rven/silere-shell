import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:     ""
    property string accessibleName: ""
    property bool   available: false
    readonly property bool interactive: root.enabled && root.available

    signal triggered()

    implicitWidth: 32
    implicitHeight: 44
    width: implicitWidth
    height: implicitHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    opacity: root.interactive ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.interactive
    Accessible.onPressAction: if (root.interactive) root.triggered()

    HoverHandler { id: _hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: _tap
        enabled: root.interactive
        onTapped: {
            root.triggered()
        }
    }

    // the fill reacts, the glyph does not: a transformed glyph is resampled, and the
    // outputs already resample every buffer once on their way to a fractional scale
    readonly property real _surfaceScale: _tap.pressed ? 0.90
        : _hover.hovered ? Motion.hoverScale : 1.0

    Rectangle {
        id: _fill
        anchors.centerIn: parent
        width: 34; height: 34; radius: Theme.radiusControl
        antialiasing: true
        scale: root._surfaceScale
        transformOrigin: Item.Center
        MotionBehavior on scale {
            NumberAnimation {
                duration: _tap.pressed ? Motion.press
                    : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        color: Theme.buttonFill(Theme.accent, _hover.hovered, _tap.pressed)

        OutlineBorder {
            radius: _fill.radius
            outlineWidth: 1
            outlineColor: Theme.buttonLine(
                Theme.accent, _hover.hovered, _tap.pressed)
            ColorFade on outlineColor {}
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
