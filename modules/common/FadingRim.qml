import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property real radius: 0
    property color rimColor: "transparent"
    property real band: 1

    anchors.fill: parent

    ShapePath {
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: 0; y2: root.height
            GradientStop { position: 0.0; color: Qt.rgba(root.rimColor.r, root.rimColor.g, root.rimColor.b, 0) }
            GradientStop { position: 0.6; color: Qt.rgba(root.rimColor.r, root.rimColor.g, root.rimColor.b, root.rimColor.a * 0.4) }
            GradientStop { position: 1.0; color: root.rimColor }
        }
        PathRectangle {
            width: root.width; height: root.height
            radius: root.radius
        }
        PathRectangle {
            x: root.band; y: root.band
            width: Math.max(0, root.width - root.band * 2)
            height: Math.max(0, root.height - root.band * 2)
            radius: Math.max(0, root.radius - root.band)
        }
    }
}
