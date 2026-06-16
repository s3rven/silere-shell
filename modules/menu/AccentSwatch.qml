import QtQuick
import "../../config"
import "../../services"

// One chip in the Theme accent picker: a tappable colour disc with a press
// ripple and a selection ring. The "auto" chip and the seven preset swatches
// share this — only the chip colour, selected state, and the inner mark differ.
// The mark is passed as the default content slot (a 2×2 grid for auto, a centre
// dot for the presets), parented into the 22px disc.
Item {
    id: root

    property color  chipColor: Theme.accent
    property bool   active:    false
    property string name:      ""
    default property alias content: _chip.data

    signal picked()
    // (name, hovered) — caller threads this into the picker's shared readout.
    signal hoverChanged(string name, bool hovered)

    width: 26; height: 32

    HoverHandler {
        id: _h
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: root.hoverChanged(root.name, hovered)
    }
    TapHandler {
        id: _t
        onTapped: { root.picked(); if (!ShellSettings.reduceMotion) _ripAnim.restart() }
    }

    // Press ripple — a ring that scales out and fades on tap.
    Rectangle {
        id: _rip
        anchors.centerIn: parent
        width: 30; height: 30; radius: 15
        color: "transparent"; border.width: 2; border.color: root.chipColor
        opacity: 0; transformOrigin: Item.Center; antialiasing: true
        ParallelAnimation {
            id: _ripAnim
            NumberAnimation { target: _rip; property: "scale";   from: 0.85; to: 1.7; duration: Motion.ms(380); easing.type: Easing.OutCubic }
            NumberAnimation { target: _rip; property: "opacity"; from: 0.7;  to: 0.0; duration: Motion.ms(380); easing.type: Easing.OutCubic }
        }
    }
    // Selection ring — solid when active, a faint preview on hover.
    Rectangle {
        anchors.centerIn: parent; width: 30; height: 30; radius: 15
        color: "transparent"; border.width: 2; border.color: root.chipColor
        opacity: root.active ? 0.85 : (_h.hovered ? 0.4 : 0.0)
        scale:   root.active ? 1.0 : (_h.hovered ? 0.92 : 0.5)
        transformOrigin: Item.Center; antialiasing: true
        Behavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
        Behavior on scale   { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 5; damping: 0.5; epsilon: 0.01 } }
    }
    Rectangle {
        id: _chip
        anchors.centerIn: parent; width: 22; height: 22; radius: 11
        antialiasing: true
        color: root.chipColor
        scale: _t.pressed ? 0.80 : root.active ? 1.0 : _h.hovered ? 1.08 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.005 } }
    }
}
