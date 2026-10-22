import QtQuick
import Quickshell
import "../../config"

Item {
    id: root

    property string label: ""
    property string glyph: ""
    property string accessibleName: label
    property bool emphasis: false
    property color accentColor: Theme.accent
    property real radius: Theme.radiusField

    signal triggered()

    readonly property bool pressed: _tap.pressed
    readonly property bool _canActivate: root.enabled && root.visible

    // 4px: any other width lands the outline stroke off-pixel under fractional scaling
    implicitWidth: Metrics.snap4Up(_row.implicitWidth + 20)
    implicitHeight: Metrics.rowHeightFor(32)
    width: implicitWidth
    height: implicitHeight
    // no scale anywhere: the surface already nudges a whole device pixel on press and lifts one
    // on hover, and scaling text resamples every glyph for as long as it lasts
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _nudge: Metrics.devicePx(1, root._dpr)
    // rows centre it and cards stretch it, so its place and width snap here rather than at every caller
    transform: PixelSnap { item: root; dpr: root._dpr }
    opacity: root.enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }
    function activate(): void {
        if (root._canActivate) root.triggered()
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root._canActivate
    Accessible.onPressAction: root.activate()

    HoverHandler {
        id: _hover
        enabled: root._canActivate
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root._canActivate
        onTapped: {
            root.activate()
        }
    }

    Rectangle {
        id: _surface
        width: Metrics.devicePx(root.width, root._dpr)
        y: root.pressed ? root._nudge : _hover.hovered ? -root._nudge : 0
        height: parent.height - y
        MotionBehavior on y {
            id: _liftMotion
            NumberAnimation {
                duration: _liftMotion.targetValue > 0 ? Motion.press
                    : _liftMotion.targetValue < 0 ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        radius: root.radius
        antialiasing: true
        color: root.emphasis
            ? Theme.emphasisButtonFill(root.accentColor, _hover.hovered, root.pressed)
            : Theme.buttonFill(root.accentColor, _hover.hovered, root.pressed)

        ColorFade on color {}

        OutlineBorder {
            radius: _surface.radius
            outlineWidth: 1
            outlineColor: root.emphasis ? "transparent"
                    : Theme.buttonLine(root.accentColor, _hover.hovered, root.pressed)

            ColorFade on outlineColor {}
        }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: root.glyph.length > 0 && root.label.length > 0 ? 7 : 0
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
