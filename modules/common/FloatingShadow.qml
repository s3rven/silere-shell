pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../services"

// Shared single-pass elevation cue for floating cards, pills, popups, and the bar.
// One broad, slightly displaced shadow reads as both ambient and contact depth
// without paying for two full-screen blur nodes per surface.
Item {
    id: root

    required property real radius
    required property bool atBottom

    // Larger surfaces (the bar) can spread the shadow a little wider.
    property real blur:   12
    property real offset: 4

    readonly property real _strength: ShellSettings.barShadowStrength
    readonly property real _alpha: Math.min(0.38, 0.24 * _strength)

    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   root.blur
        offset: Qt.vector2d(0, root.atBottom ? -root.offset : root.offset)
        color:  Qt.rgba(0, 0, 0, root._alpha)
    }
}
