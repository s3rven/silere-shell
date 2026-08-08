import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:     ""
    property string accessibleName: "Media control"
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

    activeFocusOnTab: root.interactive
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.interactive
    Accessible.pressed: _tap.pressed
    Accessible.onPressAction: if (root.interactive) root.triggered()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat && root.interactive) root.triggered(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat && root.interactive) root.triggered(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat && root.interactive) root.triggered(); event.accepted = true }

    HoverHandler { id: _hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler   { id: _tap;   enabled: root.interactive; onTapped: root.triggered() }

    scale: _tap.pressed ? 0.86 : 1.0; transformOrigin: Item.Center
    MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    Rectangle {
        id: _fill
        anchors.centerIn: parent
        width: 34; height: 34; radius: Theme.radiusControl
        antialiasing: true
        color: Theme.withAlpha(Theme.text, _tap.pressed ? 0.10 : 0.06)
        opacity: (_hover.hovered || _tap.pressed || root.activeFocus) ? 1.0 : 0.0

        OutlineBorder {
            radius: _fill.radius
            outlineWidth: 2
            outlineColor: root.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingAlpha) : "transparent"
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
        font.family: Settings.font; font.pixelSize: Settings.fontSize + 8
        ColorFade on color {}
    }
}
