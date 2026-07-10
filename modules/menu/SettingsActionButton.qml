import QtQuick
import "../../config"

Item {
    id: root

    property string label: ""
    property string glyph: ""
    property string accessibleName: label
    property bool emphasis: false
    property bool confirm: false
    property bool armed: false
    property int confirmTimeout: 3000
    property color accentColor: Theme.accent

    signal triggered()

    readonly property real contentWidth: _row.implicitWidth + 22
    readonly property bool _emphasis: root.emphasis || root.armed
    readonly property color _accent: root.armed ? Theme.error : root.accentColor

    height: 34
    opacity: root.enabled ? 1.0 : 0.42

    function disarm(): void { root.armed = false }
    function activate(): void {
        if (!root.enabled) return
        if (!root.confirm || root.armed) {
            root.disarm()
            root.triggered()
        } else {
            root.armed = true
            _armTimer.restart()
        }
    }

    Timer { id: _armTimer; interval: root.confirmTimeout; onTriggered: root.disarm() }
    onEnabledChanged: if (!root.enabled) root.disarm()

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.description: root.armed ? "Activate again to confirm" : ""
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
        color: root._emphasis
            ? Theme.mix(Theme.menuControl, root._accent, _hover.hovered || root.armed ? 0.34 : 0.26)
            : (_hover.hovered ? Theme.withAlpha(Theme.subtext, 0.16) : Theme.menuControl)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? Theme.withAlpha(root._accent, 0.82)
            : root._emphasis
                ? Theme.withAlpha(root._accent, 0.48)
                : _hover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root._emphasis ? root._accent : Theme.withAlpha(Theme.subtext, 0.90)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
            }
            Text {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.armed ? "Press again" : root.label
                color: root._emphasis ? Theme.text : Theme.withAlpha(Theme.text, 0.84)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.weight: root._emphasis ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
            }
        }
    }
}
