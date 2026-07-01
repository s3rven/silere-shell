pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../services"

// Two-layer drop shadow for floating cards/pills/popups, same elevation cue
// used by the bar, OSD, notifications, and tray menu.
Item {
    id: root

    required property real radius
    required property bool atBottom

    readonly property real _strength: ShellSettings.barShadowStrength

    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   14
        offset: Qt.vector2d(0, root.atBottom ? -2 : 2)
        color:  Qt.rgba(0, 0, 0, Math.min(0.28, 0.13 * root._strength))
    }
    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   7
        offset: Qt.vector2d(0, root.atBottom ? -5 : 5)
        color:  Qt.rgba(0, 0, 0, Math.min(0.44, 0.26 * root._strength))
    }
}
