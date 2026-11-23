import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../config/PixelGeometry.js" as PixelGeometry

// filled clockwise from the top in whole percents and never animated: a glide fed by a 2 s poll redraws the bar for its length on every poll
Shape {
    id: root

    property real  value: 0
    property real  strokeWidth: 2
    property color trackColor: "transparent"
    property color arcColor: "transparent"

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _stroke: PixelGeometry.stroke(root.strokeWidth, root._dpr)
    readonly property real _radius: Math.max(0.5, (Math.min(root.width, root.height) - root._stroke) / 2)
    readonly property real _shown: Math.round(Math.max(0, Math.min(1, root.value)) * 100) / 100

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: root._stroke
        strokeColor: root.trackColor
        fillColor: "transparent"
        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: root._radius
            radiusY: root._radius
            startAngle: -90
            sweepAngle: 360
        }
    }

    ShapePath {
        strokeWidth: root._stroke
        strokeColor: root._shown <= 0 ? "transparent" : root.arcColor
        // flat: a round cap reaches past each end, so 2% drew a dot and 97% a closed ring
        capStyle: ShapePath.FlatCap
        fillColor: "transparent"
        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: root._radius
            radiusY: root._radius
            startAngle: -90
            sweepAngle: 360 * root._shown
        }
    }
}
