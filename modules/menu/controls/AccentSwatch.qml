import QtQuick
import "../../../config"

Item {
    id: root

    property color  chipColor: Theme.accent
    property color  ringColor: chipColor
    property bool   active:    false
    property string name:      ""
    property string groupLabel: ""
    default property alias content: _chip.data

    signal picked()
    signal hoverChanged(string name, bool hovered)

    function _activate(): void { if (root.enabled) root.picked() }

    implicitWidth: 26
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        id: _h
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: root.hoverChanged(root.name, hovered)
    }
    TapHandler {
        id: _t
        enabled: root.enabled
        onTapped: {
            root._activate()
        }
    }

    Rectangle {
        id: _chip
        anchors.centerIn: parent; width: 22; height: 22; radius: 11
        antialiasing: true
        color: root.chipColor
        scale: _t.pressed ? 0.90 : _h.hovered ? 1.04 : 1.0
        transformOrigin: Item.Center
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
