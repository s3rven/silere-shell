import QtQuick

// rounded-rect perimeter: a full track outline plus a progress stroke walked by
// arc length, so corners advance at the same rate as the straights
Canvas {
    id: root

    property real  progress: 0
    property real  inset: 1.0
    property real  cornerRadius: 8
    property color trackColor: "transparent"
    property color arcColor: "transparent"
    property real  trackWidth: 1
    property real  arcWidth: 1.5

    antialiasing: true
    renderTarget:   Canvas.Image
    renderStrategy: Canvas.Threaded

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (width <= 0 || height <= 0) return

        const x = root.inset
        const y = root.inset
        const w = width  - root.inset * 2
        const h = height - root.inset * 2
        if (w <= 0 || h <= 0) return
        const r  = Math.max(0.5, Math.min(root.cornerRadius - root.inset, Math.min(w, h) / 2))
        const sx = Math.max(0, w - 2 * r)
        const sy = Math.max(0, h - 2 * r)
        const ar = Math.PI / 2 * r

        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.arc(x + w - r, y + r,     r, -Math.PI / 2, 0)
        ctx.lineTo(x + w, y + h - r)
        ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2)
        ctx.lineTo(x + r, y + h)
        ctx.arc(x + r, y + h - r,     r, Math.PI / 2, Math.PI)
        ctx.lineTo(x, y + r)
        ctx.arc(x + r, y + r,         r, Math.PI, 3 * Math.PI / 2)
        ctx.lineWidth   = root.trackWidth
        ctx.strokeStyle = root.trackColor
        ctx.stroke()

        const p = Math.max(0, Math.min(1, root.progress))
        if (p <= 0.002) return
        let t = p * (2 * sx + 2 * sy + 4 * ar)

        let l
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        l = Math.min(t, sx); ctx.lineTo(x + r + l, y); t -= l
        if (t > 0) { l = Math.min(t, ar); ctx.arc(x + w - r, y + r,     r, -Math.PI / 2, -Math.PI / 2 + l / r); t -= l }
        if (t > 0) { l = Math.min(t, sy); ctx.lineTo(x + w, y + r + l); t -= l }
        if (t > 0) { l = Math.min(t, ar); ctx.arc(x + w - r, y + h - r, r, 0, l / r); t -= l }
        if (t > 0) { l = Math.min(t, sx); ctx.lineTo(x + w - r - l, y + h); t -= l }
        if (t > 0) { l = Math.min(t, ar); ctx.arc(x + r, y + h - r,     r, Math.PI / 2, Math.PI / 2 + l / r); t -= l }
        if (t > 0) { l = Math.min(t, sy); ctx.lineTo(x, y + h - r - l); t -= l }
        if (t > 0) { l = Math.min(t, ar); ctx.arc(x + r, y + r,         r, Math.PI, Math.PI + l / r); t -= l }
        ctx.lineWidth   = root.arcWidth
        ctx.lineCap     = "round"
        ctx.strokeStyle = root.arcColor
        ctx.stroke()
    }

    property real _painted: -1
    // cap to ~33fps and skip sub-pixel travel — the arc otherwise ticks every
    // vsync frame, each one a threaded-canvas upload. 0 for a driver that already
    // paces itself, where a second gate just eats frames to jitter.
    property int minPaintMs: 30
    property real _lastPaintMs: 0

    function _commitPaint(): void {
        root._painted = root.progress
        root._lastPaintMs = Date.now()
        root.requestPaint()
    }

    function _invalidate(): void {
        if (root.visible) root._commitPaint()
    }

    function _queueProgressPaint(): void {
        if (!root.visible) return
        const now = Date.now()
        const endpoint = root.progress <= 0.002 || root.progress >= 0.998
        if (!endpoint && Math.abs(root.progress - root._painted)
                * 2 * (root.width + root.height) < 1.0) return
        const wait = root.minPaintMs - (now - root._lastPaintMs)
        if (wait > 0) {
            _paintDelay.interval = Math.max(1, Math.ceil(wait))
            _paintDelay.restart()
            return
        }
        _paintDelay.stop()
        root._commitPaint()
    }

    Timer {
        id: _paintDelay
        onTriggered: root._commitPaint()
    }

    onProgressChanged: _queueProgressPaint()
    onVisibleChanged: {
        if (visible) {
            _lastPaintMs = 0
            _commitPaint()
        } else {
            _paintDelay.stop()
        }
    }
    onWidthChanged:        _invalidate()
    onHeightChanged:       _invalidate()
    onInsetChanged:        _invalidate()
    onCornerRadiusChanged: _invalidate()
    onTrackColorChanged:   _invalidate()
    onArcColorChanged:     _invalidate()
    onTrackWidthChanged:   _invalidate()
    onArcWidthChanged:     _invalidate()
}
