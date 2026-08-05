import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property color  chipColor: Theme.accent
    property color  ringColor: chipColor
    property bool   active:    false
    property bool   tabFocusable: true
    property string name:      ""
    property string groupLabel: ""
    default property alias content: _chip.data

    signal picked()
    signal hoverChanged(string name, bool hovered)

    function _activate(): void { root.picked() }

    width: 26; height: 32

    activeFocusOnTab: root.enabled && root.tabFocusable
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.groupLabel.length > 0 ? root.groupLabel + ": " + root.name : root.name
    Accessible.checkable: true
    Accessible.checked: root.active
    Accessible.onPressAction: root._activate()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }

    HoverHandler {
        id: _h
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: root.hoverChanged(root.name, hovered)
    }
    TapHandler {
        id: _t
        onTapped: root._activate()
    }

    Rectangle {
        id: _focusRing
        anchors.fill: parent
        anchors.margins: 1
        radius: 8
        antialiasing: true
        color: root.activeFocus
            ? Theme.withAlpha(root.ringColor, 0.07)
            : "transparent"
        ColorFade on color {}

        OutlineBorder {
            radius: _focusRing.radius
            outlineColor: root.activeFocus ? Theme.withAlpha(root.ringColor, Theme.focusRingSoftAlpha) : "transparent"
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
