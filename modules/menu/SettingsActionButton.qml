import QtQuick
import "../../config"

Item {
    id: root

    property string label: ""
    property string glyph: ""
    property bool emphasis: false
    property color accentColor: Theme.accent

    signal triggered()

    readonly property real contentWidth: _row.implicitWidth + 22

    height: 34
    opacity: root.enabled ? 1.0 : 0.42

    function activate(): void {
        if (root.enabled) root.triggered()
    }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }

    HoverHandler {
        id: _hover
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: root.enabled
        onTapped: root.activate()
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        antialiasing: true
        color: root.emphasis
            ? Theme.mix(Theme.menuControl, root.accentColor, _hover.hovered ? 0.34 : 0.26)
            : (_hover.hovered ? Theme.withAlpha(Theme.subtext, 0.16) : Theme.menuControl)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? Theme.withAlpha(root.accentColor, 0.82)
            : root.emphasis
                ? Theme.withAlpha(root.accentColor, 0.48)
                : Theme.menuControlLine

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root.emphasis ? root.accentColor : Theme.withAlpha(Theme.subtext, 0.90)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
            }
            Text {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.emphasis ? Theme.text : Theme.withAlpha(Theme.text, 0.84)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.weight: root.emphasis ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
            }
        }
    }
}
