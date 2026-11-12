import QtQuick
import Quickshell
import "../../../config"
import "../../../services"

Canvas {
    id: _viz
    anchors.fill: parent

    property var screen: null
    property bool lowPower: false
    property bool presentationActive: true
    property real edgeFadeMax: 22
    property real barWidthMax: 7
    // trace the surface's lower edge: its corner arcs carry the line and the spectrum rides the straight run between them
    property bool followRim: false
    property real rimRadius: 0
    // transparent margin each side, where a snapped canvas overhangs the surface
    property real rimInset: 0
    readonly property bool _onActiveBar: Monitors.isActive(screen)
    readonly property string _style: ShellSettings.mediaVisualizerStyle
    property bool _registered: false
    property bool _registeredLowPower: false

    // a parent that fades us out needs the last frame to survive the fade; painting and the cava client still stop at once
    property bool holdFrame: false
    readonly property bool _live: presentationActive && ShellSettings.mediaProgress
        && !ShellSettings.reduceMotion && !Idle.isQuiet
        && Media.shown && Media.playing && Media.cavaReady && _onActiveBar
        && width > 0 && height > 0

    visible: _live || (holdFrame && width > 0 && height > 0)
    renderTarget: Canvas.Image
    // frozen once the context exists; binding it only logs "not changeable" and silently keeps the construction-time value
    renderStrategy: Canvas.Immediate

    property var waveData: Media.barHeights
    readonly property bool _paintable: _live
    onWaveDataChanged:  if (_paintable) requestPaint()
    onWidthChanged:     if (_paintable) requestPaint()
    onHeightChanged:    if (_paintable) requestPaint()
    onEdgeFadeMaxChanged: if (_paintable) requestPaint()
    onBarWidthMaxChanged: if (_paintable) requestPaint()
    onRimRadiusChanged: if (_paintable) requestPaint()
    onRimInsetChanged:  if (_paintable) requestPaint()
    onVisibleChanged:   if (_paintable) requestPaint()
    on_PaintableChanged: {
        _syncRegistration()
        if (_paintable) requestPaint()
    }
    onLowPowerChanged: _syncRegistration()

    Connections {
        target: ShellSettings
        function onMediaVisualizerStyleChanged() { if (_viz._paintable) _viz.requestPaint() }
    }

    Connections {
        target: Theme
        function onBarAccentChanged() { if (_viz._paintable) _viz.requestPaint() }
    }

    property var   _fill:   null
    property var   _stroke: null
    property var   _barFill: null
    property real  _barFillH: -1
    property real  _barFillR: -1
    property real  _barFillG: -1
    property real  _barFillB: -1
    property var   _edgeL:  null
    property var   _edgeR:  null
    property real  _fillH:  -1
    property real  _fillR:  -1
    property real  _fillG:  -1
    property real  _fillB:  -1
    property real  _edgeW:  -1
    property real  _edgeFadeW: -1
    property real  _edgeSide: -1
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

    // playback status gates this; one rect, not a second pass over the path
    readonly property bool _progressSplit: ShellSettings.mediaWidgetHelper && Media.lengthKnown
    on_ProgressSplitChanged: if (_paintable) requestPaint()

    function _dimAhead(ctx, left, span) {
        if (!_progressSplit) return
        var playX = Math.round(left + span * Math.max(0, Math.min(1, Media.positionRatio)))
        if (playX >= left + span - 0.5) return
        ctx.globalCompositeOperation = "destination-out"
        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.62)
        ctx.fillRect(playX, 0, width - playX, height)
        ctx.globalCompositeOperation = "source-over"
    }

    function _finish(ctx) {
        var side = followRim ? Math.max(0, rimInset) : 0
        _dimAhead(ctx, side, width - side * 2)
        _fadeEdges(ctx)
    }

    // destination-out, not destination-in: in erases every pixel the source misses, so it would
    // have to cover the whole canvas to preserve a middle it never actually changes
    function _fadeEdges(ctx) {
        var side = followRim ? Math.max(0, rimInset) : 0
        // a rim keeps the arc's lower half lit and lets it dissolve as it climbs the side
        var fadeW = followRim ? Math.max(12, _rimR() * 0.75) : Math.min(width * 0.18, edgeFadeMax)
        if (fadeW <= 0.5) return
        if (!_edgeL || _edgeW !== width || _edgeFadeW !== fadeW || _edgeSide !== side) {
            var l = ctx.createLinearGradient(side, 0, side + fadeW, 0)
            l.addColorStop(0.0, "black")
            l.addColorStop(1.0, "transparent")
            var r = ctx.createLinearGradient(width - side - fadeW, 0, width - side, 0)
            r.addColorStop(0.0, "transparent")
            r.addColorStop(1.0, "black")
            _edgeL = l; _edgeR = r; _edgeW = width; _edgeFadeW = fadeW; _edgeSide = side
        }
        ctx.globalCompositeOperation = "destination-out"
        ctx.fillStyle = _edgeL
        ctx.fillRect(0, 0, side + fadeW, height)
        ctx.fillStyle = _edgeR
        ctx.fillRect(width - side - fadeW, 0, side + fadeW, height)
        ctx.globalCompositeOperation = "source-over"
    }

    readonly property real _rimEdge: 0.75
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    function _rimR(): real {
        return Math.max(0, Math.min(rimRadius, (width - rimInset * 2) / 2))
    }
    // spectrum motion eases out where the straight run meets an arc, so the line turns the corner at rest
    function _taper(x, x0, x1): real {
        var ramp = Math.min(36, (x1 - x0) * 0.12)
        if (ramp <= 0) return 1
        var a = Math.max(0, Math.min(1, (x - x0) / ramp))
        var b = Math.max(0, Math.min(1, (x1 - x) / ramp))
        return a * a * (3 - 2 * a) * b * b * (3 - 2 * b)
    }
    function _rimArcLeft(ctx, x0, r) {
        var e = _rimEdge
        if (r <= e) { ctx.moveTo(x0, height - e); return }
        ctx.moveTo(x0 - r + e, height - r)
        ctx.arc(x0, height - r, r - e, Math.PI, Math.PI / 2, true)
    }
    function _rimArcRight(ctx, x1, r) {
        var e = _rimEdge
        ctx.lineTo(x1, height - e)
        if (r > e) ctx.arc(x1, height - r, r - e, Math.PI / 2, 0, true)
    }
    // bar centres are quadratic control points and the curve passes through their midpoints
    function _traceWave(ctx, cy, x0, slot, n, endX, endY) {
        for (var i = 0; i < n - 1; i++) {
            var cpx = x0 + slot * (i + 0.5)
            var nxt = x0 + slot * (i + 1.5)
            ctx.quadraticCurveTo(cpx, cy[i], (cpx + nxt) * 0.5, (cy[i] + cy[i + 1]) * 0.5)
        }
        ctx.quadraticCurveTo(x0 + slot * (n - 0.5), cy[n - 1], endX, endY)
    }

    function _setRegistered(want: bool): void {
        if (want) {
            if (_registered && _registeredLowPower !== lowPower) {
                Media.updateVisualizerPower(_registeredLowPower, lowPower)
                _registeredLowPower = lowPower
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

        var rim   = followRim
        var rr    = rim ? _rimR() : 0
        var x0    = rim ? rimInset + rr : 0
        var x1    = rim ? width - rimInset - rr : width
        var base  = rim ? height - _rimEdge : height
        var slot  = (x1 - x0) / n
        var maxPx = height * 0.75
        var ac    = Theme.barAccent
        if (slot <= 0) return

        var cy = _cy
        if (cy.length !== n) { cy = new Array(n); _cy = cy }
        for (var k = 0; k < n; k++)
            cy[k] = base - (h[k] ?? 0) * maxPx * (rim ? _taper(x0 + slot * (k + 0.5), x0, x1) : 1)

        if (_style === "bars") {
            var barW = Math.max(2, Math.min(barWidthMax, slot * 0.46))
            var radius = Math.min(barW * 0.5, 3)
            // fade toward the top: a peak behind the media title would otherwise paint over its glyphs
            if (!_barFill || _barFillH !== height || _barFillR !== ac.r || _barFillG !== ac.g || _barFillB !== ac.b) {
                var bg = ctx.createLinearGradient(0, 0, 0, height)
                bg.addColorStop(0.0, Qt.rgba(ac.r, ac.g, ac.b, 0.12))
                bg.addColorStop(1.0, Qt.rgba(ac.r, ac.g, ac.b, 0.82))
                _barFill = bg
                _barFillH = height
                _barFillR = ac.r
                _barFillG = ac.g
                _barFillB = ac.b
            }
            ctx.fillStyle = _barFill
            // one path holds every bar: a fill per bar was a painter pass per bar on every cava frame
            ctx.beginPath()
            for (var b = 0; b < n; b++) {
                var bh = Math.max(1.5, base - cy[b])
                var x = Math.round(x0 + slot * b + (slot - barW) * 0.5)
                var y = height - bh
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + barW - radius, y)
                ctx.quadraticCurveTo(x + barW, y, x + barW, y + radius)
                ctx.lineTo(x + barW, height)
                ctx.lineTo(x, height)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.closePath()
            }
            ctx.fill()
            _finish(ctx)
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
            if (rim) _rimArcLeft(ctx, x0, rr)
            else ctx.moveTo(1, lineY)
            for (var q = 0; q < n; q++) {
                var px = x0 + slot * (q + 0.5)
                var py = base - (0.25 + (h[q] ?? 0) * 0.75) * maxPx
                    * (rim ? _taper(px, x0, x1) : 1)
                ctx.lineTo(px, py)
            }
            if (rim) _rimArcRight(ctx, x1, rr)
            else ctx.lineTo(width - 1, lineY)
            ctx.stroke()

            var glowH = Math.max(3, avg * height)
            var glowBucket = Math.max(1, Math.min(Math.ceil(height), Math.round(glowH)))
            ctx.fillStyle = _pulseFill(ctx, glowBucket, ac)
            ctx.globalAlpha = 0.18 + avg * 0.20
            ctx.fillRect(x0, height - glowBucket, x1 - x0, glowBucket)
            ctx.globalAlpha = 1.0
            _finish(ctx)
            return
        }

        if (!_fill || _fillH !== height || _fillR !== ac.r || _fillG !== ac.g || _fillB !== ac.b) {
            var g = ctx.createLinearGradient(0, 0, 0, height)
            g.addColorStop(0.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.0))
            g.addColorStop(0.72, Qt.rgba(ac.r, ac.g, ac.b, 0.13))
            g.addColorStop(1.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.32))
            _fill = g
            // quiet through the text band: a full-strength crest behind the media title reads as a strikethrough
            var sg = ctx.createLinearGradient(0, 0, 0, height)
            sg.addColorStop(0.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.10))
            sg.addColorStop(0.62, Qt.rgba(ac.r, ac.g, ac.b, 0.28))
            sg.addColorStop(1.0,  Qt.rgba(ac.r, ac.g, ac.b, 0.85))
            _stroke = sg
            _fillH = height
            _fillR = ac.r
            _fillG = ac.g
            _fillB = ac.b
        }

        ctx.lineWidth   = 1.5
        ctx.lineJoin    = "round"
        ctx.lineCap     = "butt"
        ctx.strokeStyle = _stroke
        ctx.fillStyle   = _fill

        if (rim) {
            // the arcs only carry the stroke; the fill sits between the wave and the straight run.
            // QPainter outlines any pen wider than a device pixel, ~2 ms a frame along a bar-wide wave,
            // so the 1.5 px line is stacked from opaque hairlines, which take its fast path, and takes
            // the stroke's fade after. A hairline blends rather than adds the two halves of the pixel
            // where curves meet, a column a tenth light; a twin one device pixel along covers it
            var px = 1 / _dpr
            // their own pixels and the gaps between span a little under the pen's 1.5 px, since the outer
            // hairlines' soft edges add the rest: ink per column within 6% of the old stroke at scale 1, 1.25, 2
            var lines = Math.max(1, Math.ceil(1.5 * _dpr))
            var step = lines > 1 ? Math.max(0, 1.5 - 0.3 * px - px) / (lines - 1) : 0
            ctx.lineWidth = 0.999 * px
            ctx.strokeStyle = Qt.rgba(ac.r, ac.g, ac.b, 1)
            for (var s = 0; s < lines * 2; s++) {
                ctx.save()
                ctx.translate((s % 2) * px, (Math.floor(s / 2) - (lines - 1) / 2) * step)
                ctx.beginPath()
                _rimArcLeft(ctx, x0, rr)
                _traceWave(ctx, cy, x0, slot, n, x1, base)
                _rimArcRight(ctx, x1, rr)
                ctx.stroke()
                ctx.restore()
            }
            ctx.globalCompositeOperation = "destination-in"
            ctx.fillStyle = _stroke
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = _fill
            ctx.beginPath()
            ctx.moveTo(x0, base)
            _traceWave(ctx, cy, x0, slot, n, x1, base)
            ctx.lineTo(x1, height)
            ctx.lineTo(x0, height)
            ctx.closePath()
            ctx.fill()
            _finish(ctx)
            return
        }

        // stroke the open wave before extending the same path down to fill - ctx.stroke() leaves the path intact
        ctx.beginPath()
        ctx.moveTo(1, cy[0])
        _traceWave(ctx, cy, 0, slot, n, width - 1, cy[n - 1])
        ctx.stroke()

        ctx.lineTo(width - 1, height)
        ctx.lineTo(1, height)
        ctx.closePath()
        ctx.fill()

        _finish(ctx)
    }
}
