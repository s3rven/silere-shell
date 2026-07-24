import QtQuick
import "../../../config"
import "../../../services"

Canvas {
    id: _viz
    anchors.fill: parent

    property string barName: ""
    property bool lowPower: false
    property string styleOverride: ""
    property bool presentationActive: true
    readonly property bool _onActiveBar: barName.length === 0 || Monitors.activeName === barName
    readonly property string _style: styleOverride.length > 0 ? styleOverride : ShellSettings.mediaVisualizerStyle
    property bool _registered: false
    property bool _registeredLowPower: false

    visible: presentationActive && (ShellSettings.mediaProgress || styleOverride.length > 0)
        && !ShellSettings.reduceMotion && !Idle.isIdle
        && Media.shown && Media.playing && Media.cavaReady && _onActiveBar
        && width > 0 && height > 0
    renderTarget:   Canvas.Image
    renderStrategy: lowPower ? Canvas.Immediate : Canvas.Threaded

    property var waveData: Media.barHeights
    readonly property bool _paintable: visible && width > 0 && height > 0
    onWaveDataChanged:  if (_paintable) requestPaint()
    onWidthChanged:     if (_paintable) requestPaint()
    onHeightChanged:    if (_paintable) requestPaint()
    onVisibleChanged:   if (_paintable) requestPaint()
    on_PaintableChanged: {
        _syncRegistration()
        if (_paintable) requestPaint()
    }
    onLowPowerChanged: _syncRegistration()

    Connections {
        target: ShellSettings
        function onMediaVisualizerStyleChanged() { if (_viz.visible) _viz.requestPaint() }
    }

    property var   _fill:   null
    property var   _edge:   null
    property real  _fillH:  -1
    property real  _fillR:  -1
    property real  _fillG:  -1
    property real  _fillB:  -1
    property real  _edgeW:  -1
    property var   _cy:     []
    property var   _pulseFills: []
    property real  _pulseH: -1
    property real  _pulseR: -1
    property real  _pulseG: -1
    property real  _pulseB: -1

    function _pulseFill(ctx, glowH, ac): var {
        if (_pulseH !== height || _pulseR !== ac.r || _pulseG !== ac.g || _pulseB !== ac.b) {
            _pulseFills = []
            _pulseH = height
            _pulseR = ac.r
            _pulseG = ac.g
            _pulseB = ac.b
        }
        var bucket = Math.max(1, Math.min(Math.ceil(height), Math.round(glowH)))
        var cached = _pulseFills[bucket]
        if (cached) return cached
        cached = ctx.createLinearGradient(0, height - bucket, 0, height)
        cached.addColorStop(0.0, Qt.rgba(ac.r, ac.g, ac.b, 0.0))
        cached.addColorStop(1.0, Qt.rgba(ac.r, ac.g, ac.b, 1.0))
        _pulseFills[bucket] = cached
        return cached
    }

    function _fadeEdges(ctx) {
        var fadeW = Math.min(width * 0.18, 22)
        if (!_edge || Math.round(_edgeW) !== Math.round(width)) {
            var m = ctx.createLinearGradient(0, 0, width, 0)
            m.addColorStop(0.0,                 "transparent")
            m.addColorStop(fadeW / width,       "black")
            m.addColorStop(1.0 - fadeW / width, "black")
            m.addColorStop(1.0,                 "transparent")
            _edge = m; _edgeW = width
        }
        ctx.globalCompositeOperation = "destination-in"
        ctx.fillStyle = _edge
        ctx.fillRect(0, 0, width, height)
        ctx.globalCompositeOperation = "source-over"
    }

    function _setRegistered(want: bool): void {
        if (want) {
            if (_registered && _registeredLowPower !== lowPower) {
                Media.unregisterVisualizer(_registeredLowPower)
                _registered = false
            }
            if (!_registered) {
                Media.registerVisualizer(lowPower)
                _registeredLowPower = lowPower
                _registered = true
            }
        } else if (_registered) {
            Media.unregisterVisualizer(_registeredLowPower)
            _registered = false
        }
    }
    function _syncRegistration(): void {
        _setRegistered(_paintable)
    }

    Component.onCompleted: _syncRegistration()
    Component.onDestruction: _setRegistered(false)

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

        if (_style === "bars") {
            var barW = Math.max(2, Math.min(7, slot * 0.46))
            var radius = Math.min(barW * 0.5, 3)
            ctx.fillStyle = Qt.rgba(ac.r, ac.g, ac.b, 0.82)
            for (var b = 0; b < n; b++) {
                var bh = Math.max(1.5, (h[b] ?? 0) * maxPx)
                var x = Math.round(slot * b + (slot - barW) * 0.5)
                var y = height - bh
                ctx.beginPath()
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + barW - radius, y)
                ctx.quadraticCurveTo(x + barW, y, x + barW, y + radius)
                ctx.lineTo(x + barW, height)
                ctx.lineTo(x, height)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.fill()
            }
            _fadeEdges(ctx)
            return
        }

        if (_style === "pulse") {
            var sum = 0
            for (var p = 0; p < n; p++) sum += h[p] ?? 0
            var avg = Math.min(1, sum / n)
            var lineY = height - Math.max(1.5, avg * maxPx)
            ctx.lineWidth = 1.5 + avg * 1.2
            ctx.lineCap = "round"
            ctx.strokeStyle = Qt.rgba(ac.r, ac.g, ac.b, 0.42 + avg * 0.45)
            ctx.beginPath()
            ctx.moveTo(1, lineY)
            for (var q = 0; q < n; q++) {
                var px = slot * (q + 0.5)
                var py = height - (0.25 + (h[q] ?? 0) * 0.75) * maxPx
                ctx.lineTo(px, py)
            }
            ctx.lineTo(width - 1, lineY)
            ctx.stroke()

            var glowH = Math.max(3, avg * height)
            var glowBucket = Math.max(1, Math.min(Math.ceil(height), Math.round(glowH)))
            ctx.fillStyle = _pulseFill(ctx, glowBucket, ac)
            ctx.globalAlpha = 0.18 + avg * 0.20
            ctx.fillRect(0, height - glowBucket, width, glowBucket)
            ctx.globalAlpha = 1.0
            _fadeEdges(ctx)
            return
        }

        if (!_fill || _fillH !== height || _fillR !== ac.r || _fillG !== ac.g || _fillB !== ac.b) {
            var g = ctx.createLinearGradient(0, 0, 0, height)
            g.addColorStop(0.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.0))
            g.addColorStop(0.72, Qt.rgba(ac.r, ac.g, ac.b, 0.13))
            g.addColorStop(1.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.32))
            _fill = g
            _fillH = height
            _fillR = ac.r
            _fillG = ac.g
            _fillB = ac.b
        }

        // build the wave path once. bar centres are quadratic control points, curve
        // passes through midpoints between centres → C1-smooth, no kinks, 1px inside each edge.
        // single-pass: stroke the open wave first (crest near y=0 where fill alpha≈0, so
        // the fill on top doesn't cover it), then extend the same path down and fill —
        // ctx.stroke() leaves the path intact so lineTo continues from the last point.
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

        _fadeEdges(ctx)
    }
}
