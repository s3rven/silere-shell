import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../config/PixelGeometry.js" as PixelGeometry

Shape {
    id: root

    property real radius: 0
    property color rimColor: "transparent"
    property real band: 1
    // flat stops ring the whole bar; the default fade leaves the top edge unlit
    property bool uniform: false

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _band: Math.min(PixelGeometry.stroke(root.band, root._dpr),
        Math.max(0, Math.min(root.width, root.height) / 2))
    readonly property real _radius: Math.max(0,
        Math.min(root.radius, Math.min(root.width, root.height) / 2))

    anchors.fill: parent
    visible: opacity > 0.001 && rimColor.a > 0 && _band > 0
    // without it Shape tessellates the corner arcs and a 1px ring facets visibly there — same reason OutlineBorder and PerimeterProgress set it
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: 0; y2: root.height
            GradientStop {
                position: 0.0
                color: Qt.rgba(root.rimColor.r, root.rimColor.g, root.rimColor.b,
                    root.uniform ? root.rimColor.a : 0)
            }
            GradientStop {
                position: 0.6
                color: Qt.rgba(root.rimColor.r, root.rimColor.g, root.rimColor.b,
                    root.rimColor.a * (root.uniform ? 1.0 : 0.4))
            }
            GradientStop { position: 1.0; color: root.rimColor }
        }
        PathRectangle {
            width: root.width; height: root.height
            radius: root._radius
        }
        PathRectangle {
            x: root._band; y: root._band
            width: Math.max(0, root.width - root._band * 2)
            height: Math.max(0, root.height - root._band * 2)
            radius: Math.max(0, root._radius - root._band)
        }
    }
}
