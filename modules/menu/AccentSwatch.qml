import QtQuick
import "../../config"
import "../../services"

// the inner mark is the default content slot, parented into the 22px disc
Item {
    id: root

    property color  chipColor: Theme.accent
    // dark chips can provide a brighter keyboard-focus colour
    property color  ringColor: chipColor
    property bool   active:    false
    property string name:      ""
    // announced ahead of the colour name so a swatch says what it is choosing
    property string groupLabel: ""
    default property alias content: _chip.data

    signal picked()
    // (name, hovered) — caller threads this into the picker's shared readout.
    signal hoverChanged(string name, bool hovered)

    function _activate(): void { root.picked() }

    width: 26; height: 32

    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.groupLabel.length > 0 ? root.groupLabel + ": " + root.name : root.name
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

    // Focus belongs to the control cell, not the colour itself. This keeps the
    // colour disc clean while keyboard navigation remains obvious.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 8
        antialiasing: true
        color: root.activeFocus
            ? Theme.withAlpha(root.ringColor, 0.07)
            : "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.withAlpha(root.ringColor, 0.52)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }
    Rectangle {
        id: _chip
        anchors.centerIn: parent; width: 22; height: 22; radius: 11
        antialiasing: true
        color: root.chipColor
        scale: _t.pressed ? 0.90 : _h.hovered ? 1.04 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
