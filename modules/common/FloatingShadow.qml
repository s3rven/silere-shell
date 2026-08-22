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
    // the strength slider's max is set to land on this ceiling; raising one without the other leaves the top of the slider doing nothing
    readonly property real _alpha: Math.min(0.38, 0.24 * _strength)

    readonly property real _keyAlpha: _alpha * 0.60
    // the two layers composite, so the ambient share is solved back out of the total —
    // without this the strength slider would read ~60% darker than it did as one layer
    readonly property real _ambientAlpha: 1 - (1 - _alpha) / (1 - _keyAlpha)

    // callers reserve exactly blur + offset of pad (Bar.effectPad, NotificationPopups._shadowPad),
    // so the ambient layer may not exceed root.blur and the contact layer stays inside it
    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   root.blur
        color:  Qt.rgba(0, 0, 0, root._ambientAlpha)
    }

    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur:   root.blur * 0.45
        offset: Qt.vector2d(0, root.atBottom ? -root.offset : root.offset)
        color:  Qt.rgba(0, 0, 0, root._keyAlpha)
    }
}
