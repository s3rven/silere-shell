import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property real  progress: 0
    property real  inset: 1.0
    property real  cornerRadius: 8
    property color trackColor: "transparent"
    property color arcColor: "transparent"
    property real  trackWidth: 1
    property real  arcWidth: 1.5
    property bool  paused: false

    property real _shownProgress: 0
    readonly property real _pathWidth: Math.max(0, width - inset * 2)
    readonly property real _pathHeight: Math.max(0, height - inset * 2)
    readonly property real _pathRadius: Math.max(0.5,
        Math.min(cornerRadius - inset, Math.min(_pathWidth, _pathHeight) / 2))
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
        strokeWidth: root.trackWidth
        strokeColor: root.trackColor
        fillColor: "transparent"

        PathRectangle {
            x: root.inset
            y: root.inset
            width: root._pathWidth
            height: root._pathHeight
            radius: root._pathRadius
        }
    }

    ShapePath {
        readonly property real _dashUnits: root._perimeter / Math.max(0.01, strokeWidth)

        strokeWidth: root.arcWidth
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
            x: root.inset
            y: root.inset
            width: root._pathWidth
            height: root._pathHeight
            radius: root._pathRadius
        }
    }
}
