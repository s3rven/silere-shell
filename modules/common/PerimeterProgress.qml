import QtQuick
import QtQuick.Shapes
import Quickshell

Shape {
    id: root

    property real  progress: 0
    property real  inset: 1.0
    property real  cornerRadius: 8
    property color trackColor: "transparent"
    property color arcColor: "transparent"
    property bool  paused: false

    property real _shownProgress: 0

    // whole device pixels with both edges on the grid; at 1.25 a 1.5px arc smeared across three pixels
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    function _snapStroke(w: real): real { return Math.max(1, Math.ceil(w * root._dpr - 0.5)) / root._dpr }
    function _snapInset(stroke: real): real {
        const half = stroke * root._dpr / 2
        return (Math.round(root.inset * root._dpr - half) + half) / root._dpr
    }
    readonly property real _trackStroke: root._snapStroke(1)
    readonly property real _arcStroke: root._snapStroke(1.5)
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

    ShapePath {
        readonly property real _dashUnits: root._perimeter / Math.max(0.01, strokeWidth)

        strokeWidth: root._arcStroke
        strokeColor: root._shownProgress <= 0.002 ? "transparent" : root.arcColor
        strokeStyle: root._shownProgress >= 0.998
            ? ShapePath.SolidLine : ShapePath.DashLine
        dashPattern: [
            Math.max(0.001, _dashUnits * root._shownProgress),
            Math.max(0.001, _dashUnits * (1 - root._shownProgress))
        ]
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"

        PathRectangle {
            x: root._arcInset
            y: root._arcInset
            width: root._pathWidth
            height: root._pathHeight
            radius: root._pathRadius
        }
    }
}
