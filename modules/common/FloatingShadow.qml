pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../services"

Item {
    id: root

    required property real radius
    required property bool atBottom

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
