import QtQuick
import QtQuick.Shapes

// uniform stroke (Rectangle.border over-weights rounded corners); 1 logical px is the floor, thinner lands sub-pixel after the fractional downscale
Shape {
    id: root

    property real radius: 0
    property real outlineWidth: 1
    property color outlineColor: "transparent"

    property real topLeftRadius: root.radius
    property real topRightRadius: root.radius
    property real bottomLeftRadius: root.radius
    property real bottomRightRadius: root.radius

    anchors.fill: parent
    visible: outlineColor.a > 0 && outlineWidth > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: root.outlineWidth
        strokeColor: root.outlineColor
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        PathRectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
            strokeAdjustment: root.outlineWidth
        }
    }
}
