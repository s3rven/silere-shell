import QtQuick
import "../../config"
import "../../services"

// the inner mark is the default content slot, parented into the 22px disc
Item {
    id: root

    property color  chipColor: Theme.accent
    // dark chips (base tones) need a ring that isn't the chip colour itself
    property color  ringColor: chipColor
    property bool   active:    false
    property string name:      ""
    default property alias content: _chip.data

    signal picked()
    // (name, hovered) — caller threads this into the picker's shared readout.
    signal hoverChanged(string name, bool hovered)

    function _activate(): void {
        root.picked()
        if (!ShellSettings.reduceMotion) _ripAnim.restart()
    }

    width: 26; height: 32

    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.name
    Accessible.checked: root.active
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
        id: _rip
        anchors.centerIn: parent
        width: 30; height: 30; radius: 15
        color: "transparent"; border.width: 2; border.color: root.ringColor
        opacity: 0; transformOrigin: Item.Center; antialiasing: true
        ParallelAnimation {
            id: _ripAnim
            NumberAnimation { target: _rip; property: "scale";   from: 0.85; to: 1.7; duration: Motion.ms(380); easing.type: Easing.OutCubic }
            NumberAnimation { target: _rip; property: "opacity"; from: 0.7;  to: 0.0; duration: Motion.ms(380); easing.type: Easing.OutCubic }
        }
    }
    Rectangle {
        anchors.centerIn: parent; width: 30; height: 30; radius: 15
        color: "transparent"; border.width: 2; border.color: root.ringColor
        opacity: (_h.hovered || root.activeFocus) ? 0.4 : 0.0
        scale:   (_h.hovered || root.activeFocus) ? 0.92 : 0.5
        transformOrigin: Item.Center; antialiasing: true
        Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
        Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
    }
    Rectangle {
        id: _chip
        anchors.centerIn: parent; width: 22; height: 22; radius: 11
        antialiasing: true
        color: root.chipColor
        scale: _t.pressed ? 0.80 : root.active ? 1.0 : _h.hovered ? 1.08 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
