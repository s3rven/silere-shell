pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
    readonly property bool _canActivate: root.enabled && root.visible

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

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
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root._canActivate
        onTapped: {
            root.activate()
        }
    }

    Rectangle {
        id: _face
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        transform: PixelScale {
            item: _face
            dpr: _face._dpr
            factor: root.pressed ? Motion.pressScale
                : _hover.hovered ? Motion.hoverScale : 1.0
        }
        color: Theme.buttonFill(root.accentColor, _hover.hovered, root.pressed)

        OutlineBorder {
            radius: width / 2
            outlineWidth: 1
            outlineColor: Theme.buttonLine(
                root.accentColor, _hover.hovered, root.pressed)
            ColorFade on outlineColor {}
        }

        ColorFade on color {}
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
