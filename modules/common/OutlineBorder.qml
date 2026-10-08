import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../config/PixelGeometry.js" as PixelGeometry

// uniform stroke (Rectangle.border over-weights rounded corners)
Shape {
    id: root

    property real radius: 0
    property real outlineWidth: 1
    property color outlineColor: "transparent"

    // the window reports the real fractional scale where the screen rounds 1.25 up to 2; whole device pixels stay crisp
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _stroke: PixelGeometry.stroke(root.outlineWidth, root._dpr)

    anchors.fill: parent
    visible: outlineColor.a > 0 && outlineWidth > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: root._stroke
        strokeColor: root.outlineColor
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        PathRectangle {
            width: root.width
            height: root.height
            radius: root.radius
            strokeAdjustment: root._stroke
        }
    }
}
