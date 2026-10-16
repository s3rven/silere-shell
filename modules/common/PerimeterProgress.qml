import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../config/PixelGeometry.js" as PixelGeometry

Shape {
    id: root

    property real  progress: 0
    property real  inset: 1.0
    property real  cornerRadius: 8
    property color trackColor: "transparent"
    property color arcColor: "transparent"
    property bool  paused: false
    property real arcWidth: 1.5

    property real _shownProgress: 0

    // whole device pixels with both edges on the grid; at 1.25 a 1.5px arc smeared across three pixels
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    function _snapStroke(w: real): real { return PixelGeometry.stroke(w, root._dpr) }
    function _snapInset(stroke: real): real {
        return PixelGeometry.inset(root.inset, stroke, root._dpr)
    }
    readonly property real _trackStroke: root._snapStroke(1)
    readonly property real _arcStroke: root._snapStroke(root.arcWidth)
    readonly property real _trackInset: root._snapInset(root._trackStroke)
    readonly property real _arcInset: root._snapInset(root._arcStroke)

    readonly property real _pathWidth: Math.max(0, width - _arcInset * 2)
    readonly property real _pathHeight: Math.max(0, height - _arcInset * 2)
    readonly property real _pathRadius: Math.max(0.5,
        Math.min(cornerRadius - _arcInset, Math.min(_pathWidth, _pathHeight) / 2))
    readonly property real _perimeter: Math.max(0.001,
        2 * (_pathWidth + _pathHeight - 4 * _pathRadius)
        + 2 * Math.PI * _pathRadius)

    preferredRendererType: Shape.CurveRenderer

    function _syncProgress(): void {
        if (!root.visible || root.paused) return
        root._shownProgress = Math.max(0, Math.min(1, root.progress))
    }

    Component.onCompleted: root._syncProgress()
    onProgressChanged: root._syncProgress()
    onPausedChanged: if (!paused) root._syncProgress()
    onVisibleChanged: if (visible) root._syncProgress()

    // one Shape keeps the static track cached and never re-uploads a texture per countdown tick, unlike Canvas
    ShapePath {
        strokeWidth: root._trackStroke
        strokeColor: root.trackColor
        fillColor: "transparent"

        PathRectangle {
            x: root._trackInset
            y: root._trackInset
            width: Math.max(0, root.width - root._trackInset * 2)
            height: Math.max(0, root.height - root._trackInset * 2)
            radius: Math.max(0.5, Math.min(root.cornerRadius - root._trackInset,
                Math.min(root.width, root.height) / 2 - root._trackInset))
        }
    }

    // centred on the top edge and shrinking evenly toward it; the path starts after the top-left corner. Full, it
    // is drawn untrimmed: two translucent round caps meeting at the top would overlap into a brighter bead
    readonly property real _topCentre: Math.max(0, _pathWidth / 2 - _pathRadius) / _perimeter
    readonly property bool _full: _shownProgress >= 0.998

    ShapePath {
        strokeWidth: root._arcStroke
        strokeColor: root._shownProgress <= 0.002 ? "transparent" : root.arcColor
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        trim.start: 0
        trim.end: root._full ? 1 : root._shownProgress
        trim.offset: root._full ? 0 : ((root._topCentre - root._shownProgress / 2) % 1 + 1) % 1

        PathRectangle {
            x: root._arcInset
            y: root._arcInset
            width: root._pathWidth
            height: root._pathHeight
            radius: root._pathRadius
        }
    }
}
