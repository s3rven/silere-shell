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

    readonly property real _lo: Math.max(0, Math.min(1, Math.min(loClamp, hiClamp)))
    readonly property real _hi: Math.max(0, Math.min(1, Math.max(loClamp, hiClamp)))
    readonly property real _c:  Math.max(_lo, Math.min(center, _hi))
    readonly property real _l:  Math.max(_lo, Math.min(_c, _c - Math.max(0, spread)))
    readonly property real _r:  Math.min(_hi, Math.max(_c, _c + Math.max(0, spread)))
    readonly property color _transparentEdge: Qt.rgba(edge.r, edge.g, edge.b, 0)

    // Sample smoothstep(t) = t*t*(3-2*t) at 1/4 and 3/4. The fixed
    // stops soften each shoulder without a shader, Canvas, or per-frame arrays.
    // Preserve alpha as well as RGB; Theme.mix intentionally returns opaque ink.
    function _mixColor(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t)
    }
    readonly property color _edgeLow: root._mixColor(_transparentEdge, edge, 0.15625)
    readonly property color _edgeHigh: root._mixColor(_transparentEdge, edge, 0.84375)
    readonly property color _shoulderLow: root._mixColor(edge, peak, 0.15625)
    readonly property color _shoulderHigh: root._mixColor(edge, peak, 0.84375)

    // Glows are soft bands; structural outlines use snapped device-pixel strokes.
    height: 1
    antialiasing: false
    visible: opacity > 0.001 && width > 0 && height > 0 && (peak.a > 0 || edge.a > 0)

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root._transparentEdge }
        GradientStop { position: root._l * 0.25; color: root._edgeLow }
        GradientStop { position: root._l * 0.75; color: root._edgeHigh }
        GradientStop { position: root._l; color: root.edge }
        GradientStop { position: root._l + (root._c - root._l) * 0.25; color: root._shoulderLow }
        GradientStop { position: root._l + (root._c - root._l) * 0.75; color: root._shoulderHigh }
        GradientStop { position: root._c; color: root.peak }
        GradientStop { position: root._c + (root._r - root._c) * 0.25; color: root._shoulderHigh }
        GradientStop { position: root._c + (root._r - root._c) * 0.75; color: root._shoulderLow }
        GradientStop { position: root._r; color: root.edge }
        GradientStop { position: root._r + (1 - root._r) * 0.25; color: root._edgeHigh }
        GradientStop { position: root._r + (1 - root._r) * 0.75; color: root._edgeLow }
        GradientStop { position: 1.0; color: root._transparentEdge }
    }
}
