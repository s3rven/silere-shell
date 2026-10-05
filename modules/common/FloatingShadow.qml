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
    // a translucent surface shows its shadow's filled interior through itself, so its set opacity reads ~9% denser
    property bool hollow: false

    readonly property real _strength: ShellSettings.barShadowStrength
    // the strength slider's max is set to land on this ceiling; raising one without the other leaves the top of the slider doing nothing
    readonly property real _alpha: Math.min(0.38, 0.24 * _strength)

    readonly property real _keyAlpha: _alpha * 0.60
    // the two layers composite, so the ambient share is solved back out of the total —
    // without this the strength slider would read ~60% darker than it did as one layer
    readonly property real _ambientAlpha: 1 - (1 - _alpha) / (1 - _keyAlpha)

    // the layer clips to its own bounds, so it reaches past the surface by everything the shadows spill
    readonly property int _pad: Math.ceil(root.blur + root.offset) + 2

    // callers reserve exactly blur + offset of pad (Bar.effectPad, NotificationPopups._shadowPad),
    // so the ambient layer may not exceed root.blur and the contact layer stays inside it
    Item {
        id: _shadows
        x: -root._pad
        y: -root._pad
        width: root.width + root._pad * 2
        height: root.height + root._pad * 2
        layer.enabled: root.hollow
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: _cutout
        }

        RectangularShadow {
            x: root._pad
            y: root._pad
            width: root.width
            height: root.height
            radius: root.radius
            blur:   root.blur
            color:  Qt.rgba(0, 0, 0, root._ambientAlpha)
        }

        RectangularShadow {
            x: root._pad
            y: root._pad
            width: root.width
            height: root.height
            radius: root.radius
            blur:   root.blur * 0.45
            offset: Qt.vector2d(0, root.atBottom ? -root.offset : root.offset)
            color:  Qt.rgba(0, 0, 0, root._keyAlpha)
        }
    }

    Item {
        id: _cutout
        x: _shadows.x
        y: _shadows.y
        width: _shadows.width
        height: _shadows.height
        visible: false
        layer.enabled: root.hollow

        // a px inside the surface edge: the shadow has to stay under the fill's antialiased rim, or a light seam opens between them
        Rectangle {
            x: root._pad + 1
            y: root._pad + 1
            width: Math.max(0, root.width - 2)
            height: Math.max(0, root.height - 2)
            radius: Math.max(0, root.radius - 1)
            antialiasing: true
            color: "black"
        }
    }
}
