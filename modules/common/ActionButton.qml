import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string label: ""
    property string glyph: ""
    property bool emphasis: false
    property color accentColor: Theme.accent
    property real radius: Theme.radiusField

    signal triggered()

    // ceil: a fractional width lands the outline stroke off-pixel under fractional scaling
    readonly property real contentWidth: implicitWidth
    readonly property bool pressed: _tap.pressed

    implicitWidth: Math.ceil(_row.implicitWidth) + 20
    implicitHeight: Metrics.rowHeightFor(32)
    width: implicitWidth
    height: implicitHeight
    scale: root.pressed ? Motion.pressScale
        : _hover.hovered ? Motion.hoverScale : 1.0
    transformOrigin: Item.Center
    opacity: root.enabled ? 1.0 : 0.42
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }
    MotionBehavior on scale {
        NumberAnimation {
            duration: root.pressed ? Motion.press
                : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
            easing.type: Easing.OutCubic
        }
    }

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: {
            root.activate()
        }
    }

    Rectangle {
        id: _surface
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.pressed ? 1 : _hover.hovered ? -1 : 0
        height: parent.height - y
        MotionBehavior on y {
            NumberAnimation {
                duration: root.pressed ? Motion.press
                    : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        radius: root.radius
        antialiasing: true
        color: root.emphasis
            ? Theme.mix(Theme.menuControl, root.accentColor,
                root.pressed ? 0.54 : _hover.hovered ? 0.48 : 0.42)
            : root.pressed
                ? Theme.withAlpha(root.accentColor, 0.12)
                : _hover.hovered
                    ? Theme.withAlpha(
                        Theme.mix(Theme.text, root.accentColor, 0.22), 0.075)
                    : Theme.withAlpha(Theme.text, 0.035)

        ColorFade on color {}

        OutlineBorder {
            radius: _surface.radius
            outlineWidth: 1
            outlineColor: root.emphasis ? "transparent"
                    : _hover.hovered
                        ? Theme.withAlpha(root.accentColor,
                            ShellSettings.highContrast ? 0.38 : 0.24)
                        : Theme.menuControlLine

            ColorFade on outlineColor {}
        }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: root.glyph.length > 0 && root.label.length > 0 ? 7 : 0
            scale: root.pressed ? 0.985 : 1.0
            transformOrigin: Item.Center

            MotionBehavior on scale {
                NumberAnimation { duration: Motion.press; easing.type: Easing.OutCubic }
            }

            ShellText {
                visible: root.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root.emphasis
                    ? Theme.mix(Theme.text, root.accentColor, 0.10)
                    : _hover.hovered
                        ? Theme.mix(Theme.subtext, root.accentColor, 0.22)
                        : Theme.withAlpha(Theme.subtext, 0.82)
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }
            ShellText {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.emphasis ? Theme.text
                    : _hover.hovered
                        ? Theme.mix(Theme.text, root.accentColor, 0.07)
                        : Theme.withAlpha(Theme.text, 0.80)
                font.pixelSize: Settings.fontLabel
                font.weight: root.emphasis ? Font.DemiBold : Font.Normal
                ColorFade on color {}
            }
        }
    }
}
