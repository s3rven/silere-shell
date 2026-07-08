pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../services"

// two-layer drop shadow for floating cards/pills/popups — shared elevation cue (bar/OSD/notifications/tray).
Item {
    id: root

    required property real radius
    required property bool atBottom

    // Larger surfaces (the bar) spread the layers a bit wider.
    property real ambientBlur:   14
    property real contactBlur:   7
    property real contactOffset: 5

    readonly property real _strength: ShellSettings.barShadowStrength

    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   root.ambientBlur
        offset: Qt.vector2d(0, root.atBottom ? -2 : 2)
        color:  Qt.rgba(0, 0, 0, Math.min(0.28, 0.13 * root._strength))
    }
    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   root.contactBlur
        offset: Qt.vector2d(0, root.atBottom ? -root.contactOffset : root.contactOffset)
        color:  Qt.rgba(0, 0, 0, Math.min(0.44, 0.26 * root._strength))
    }
}
