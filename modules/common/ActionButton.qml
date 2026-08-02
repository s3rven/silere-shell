import QtQuick
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

    // ceil: a fractional width lands the outline stroke off-pixel under fractional scaling
    readonly property real contentWidth: implicitWidth
    property bool _keyboardPressed: false
    readonly property bool pressed: _tap.pressed || root._keyboardPressed

    implicitWidth: Math.ceil(_row.implicitWidth) + 20
    implicitHeight: 4 * Math.ceil(Math.max(32, Settings.capHeight + 14) / 4)
    width: implicitWidth
    height: implicitHeight
    opacity: root.enabled ? 1.0 : 0.42
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    onEnabledChanged: if (!root.enabled) root._keyboardPressed = false
    onActiveFocusChanged: if (!activeFocus) root._keyboardPressed = false

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.pressed: root.pressed
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
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: root.activate()
    }

    Rectangle {
        id: _surface
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.pressed ? 1 : 0
        height: parent.height - y
        radius: root.radius
        antialiasing: true
        color: root.emphasis
            ? Theme.mix(Theme.menuControl, root.accentColor,
                root.pressed ? 0.54 : _hover.hovered ? 0.48 : 0.42)
            : root.pressed
                ? Theme.withAlpha(Theme.text, 0.11)
                : Theme.withAlpha(Theme.text, _hover.hovered ? 0.065 : 0.035)

        ColorFade on color {}

        OutlineBorder {
            radius: _surface.radius
            outlineWidth: root.activeFocus ? 2 : 1
            outlineColor: root.activeFocus
                ? Theme.withAlpha(root.accentColor, 0.82)
                : root.emphasis ? "transparent"
                    : _hover.hovered
                        ? Theme.menuControlLineHot : Theme.menuControlLine

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
                    : Theme.withAlpha(Theme.subtext, _hover.hovered ? 0.96 : 0.82)
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }
            ShellText {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.emphasis ? Theme.text
                    : Theme.withAlpha(Theme.text, _hover.hovered ? 0.94 : 0.80)
                font.pixelSize: Settings.fontSize - 1
                font.weight: root.emphasis ? Font.DemiBold : Font.Normal
                ColorFade on color {}
            }
        }
    }
}
