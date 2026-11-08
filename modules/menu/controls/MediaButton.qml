import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:     ""
    property string accessibleName: ""
    property bool   available: false
    property bool   lit: false
    readonly property bool interactive: root.enabled && root.visible && root.available

    signal triggered()

    function activate(): void {
        if (root.interactive) root.triggered()
    }

    implicitWidth: 40
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
    Accessible.onPressAction: root.activate()
    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

    HoverHandler { id: _hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: _tap
        enabled: root.interactive
        onTapped: {
            root.activate()
        }
    }

    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.lit ? (_hover.hovered || _tap.pressed ? Theme.mix(Theme.accent, Theme.text, 0.35) : Theme.accent)
            : _hover.hovered || _tap.pressed ? Theme.withAlpha(Theme.text, 0.92) : Theme.withAlpha(Theme.text, 0.55)
        font.pixelSize: Settings.fontSize + 9
        ColorFade on color {}
    }
}
