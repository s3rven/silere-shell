import QtQuick
import QtQuick.Shapes

// uniform rounded-rect stroke; Rectangle.border over-weights rounded corners
Shape {
    id: root

    property real radius: 0
    property real outlineWidth: 1
    property color outlineColor: "transparent"

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
            radius: root.radius
            strokeAdjustment: root.outlineWidth
        }
    }
}
