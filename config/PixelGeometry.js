.pragma library

// Match thin strokes to whole device pixels, rounding exact halves down so a
// one-pixel line does not become heavier when moved onto a 1.5x output.
function stroke(width, dpr) {
    if (width <= 0) return 0
    return Math.max(1, Math.ceil(width * dpr - 0.5)) / dpr
}

// A centered stroke needs its centerline half a stroke inside the pixel grid.
function inset(value, width, dpr) {
    const half = width * dpr / 2
    return (Math.round(value * dpr - half) + half) / dpr
}
