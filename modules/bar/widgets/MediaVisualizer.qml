import QtQuick
import "../../../config"
import "../../../services"

Canvas {
    id: _viz
    anchors.fill: parent
    visible: Media.shown && Media.playing && Media.cavaReady
    renderTarget:   Canvas.Image
    renderStrategy: Canvas.Threaded

    property var waveData: Media.barHeights
    onWaveDataChanged:  if (visible) requestPaint()
    onWidthChanged:     if (visible) requestPaint()
    onHeightChanged:    if (visible) requestPaint()
    onVisibleChanged:   if (visible) requestPaint()

    // Gradients cached, rebuilt only when their inputs change, so paint allocates nothing.
    property var   _fill:   null
    property var   _edge:   null
    property real  _fillH:  -1
    property color _fillAc: "transparent"
    property real  _edgeW:  -1
    property var   _cy:     []

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!width || !height) return

        var h = waveData
        var n = h.length
        if (!n) return

        var slot  = width / n
        var maxPx = height * 0.75
        var ac    = Theme.accent

        var cy = _cy
        if (cy.length !== n) { cy = new Array(n); _cy = cy }
        for (var k = 0; k < n; k++) cy[k] = height - (h[k] ?? 0) * maxPx

        if (!_fill || _fillH !== height || _fillAc !== ac) {
            var g = ctx.createLinearGradient(0, 0, 0, height)
            g.addColorStop(0.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.0))
            g.addColorStop(0.72, Qt.rgba(ac.r, ac.g, ac.b, 0.13))
            g.addColorStop(1.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.32))
            _fill = g; _fillH = height; _fillAc = ac
        }

        // Build the wave path once. Smoothing: bar centres are quadratic control
        // points; the curve passes through midpoints between adjacent centres →
        // C1-smooth, no kinks. Path stays 1px inside each edge.
        //
        // Single-pass: stroke the open wave first (crest sits near y=0 where
        // fill alpha≈0, so the fill painted on top doesn't cover the line),
        // then extend the live path with bottom-closing segments and fill.
        // ctx.stroke() leaves the path intact so lineTo continues from the
        // last point — no second traversal needed.
        ctx.beginPath()
        ctx.moveTo(1, cy[0])
        for (var i = 0; i < n - 1; i++) {
            var cpx = slot * (i + 0.5)
            var nxt = slot * (i + 1.5)
            ctx.quadraticCurveTo(cpx, cy[i], (cpx + nxt) * 0.5, (cy[i] + cy[i + 1]) * 0.5)
        }
        ctx.quadraticCurveTo(slot * (n - 0.5), cy[n - 1], width - 1, cy[n - 1])

        ctx.lineWidth   = 1.5
        ctx.lineJoin    = "round"
        ctx.lineCap     = "butt"
        ctx.strokeStyle = Qt.rgba(ac.r, ac.g, ac.b, 0.85)
        ctx.stroke()

        ctx.lineTo(width - 1, height)
        ctx.lineTo(1, height)
        ctx.closePath()
        ctx.fillStyle = _fill
        ctx.fill()

        // Edge fade mask — applied after fill + stroke so both fade together.
        var fadeW = Math.min(width * 0.18, 22)
        if (!_edge || _edgeW !== width) {
            var m = ctx.createLinearGradient(0, 0, width, 0)
            m.addColorStop(0.0,                "transparent")
            m.addColorStop(fadeW / width,      "black")
            m.addColorStop(1.0 - fadeW / width, "black")
            m.addColorStop(1.0,                "transparent")
            _edge = m; _edgeW = width
        }
        ctx.globalCompositeOperation = "destination-in"
        ctx.fillStyle = _edge
        ctx.fillRect(0, 0, width, height)
        ctx.globalCompositeOperation = "source-over"
    }
}
