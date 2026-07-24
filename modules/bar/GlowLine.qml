pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root

    property color peak
    property color edge
    property real  center: 0.5
    property real  spread: 0.28
    property real  loClamp: 0.02
    property real  hiClamp: 0.98

    readonly property real _lo: Math.min(loClamp, hiClamp)
    readonly property real _hi: Math.max(loClamp, hiClamp)
    readonly property real _c:  Math.max(_lo, Math.min(center, _hi))
    readonly property real _l:  Math.max(_lo, Math.min(_c, _c - Math.max(0, spread)))
    readonly property real _r:  Math.min(_hi, Math.max(_c, _c + Math.max(0, spread)))
    readonly property color _transparentEdge: Qt.rgba(edge.r, edge.g, edge.b, 0)

    height: 1
    antialiasing: false

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root._transparentEdge }
        GradientStop { position: root._l; color: root.edge }
        GradientStop { position: root._c; color: root.peak }
        GradientStop { position: root._r; color: root.edge }
        GradientStop { position: 1.0; color: root._transparentEdge }
    }
}
