import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../config"
import "../../services"

Item {
    id: root

    property real value: 0
    property color color: Theme.accent
    property color trackColor: Theme.menuTrack
    property real thickness: 3
    property real amplitude: 2
    property real wavelength: 14
    // room left clear on each side of the level, where a thumb sits
    property real endInset: 0
    property bool flowing: false
    property int flowMs: 1600
    property real waveOpacity: 1
    // how much of the level shows, left to right; a clip, so animating it never rebuilds the path
    property real reveal: 1
    MotionBehavior on amplitude { NumberAnimation { duration: Motion.slow; easing.type: Easing.OutCubic } }

    implicitHeight: Metrics.snap4Up(thickness + amplitude * 2 + 2)

    readonly property real _level: Math.max(0, Math.min(root.width, root.width * Math.max(0, Math.min(1, root.value))))
    readonly property real _waveEnd: Math.max(0, root._level - root.endInset)
    readonly property real _trackStart: Math.min(root.width,
        root._level + (root._level > 0 ? Math.max(root.endInset, root.thickness) : 0))
    // an outside offset, such as an intro; the flow adds its own on top
    property real phase: 0
    // accumulated, so a flow resumes where it stopped instead of snapping back to the start of its cycle
    property real _flow: 0
    readonly property real _phase: root.phase + root._flow

    readonly property real _len: Math.max(0, root._waveEnd - root.thickness)
    readonly property real _endX: root.thickness / 2 + root._len
    readonly property real _waveLength: Math.max(4, root.wavelength)
    // a level shorter than a wavelength reads as a stray tick, so the wave grows in with length
    readonly property real _amp: root.amplitude
        * Math.max(0, Math.min(1, (root._len - root._waveLength * 0.5) / root._waveLength))

    // a sine as cubic segments a quarter wave long, which the curve renderer draws exactly; a fine polyline left a joint every pixel or two.
    // the amplitude tapers to nothing over half a wave at each end, so the line grows out of the track's centre and lands back on it
    // wherever the level stops; a constant one broke off at whatever height the length happened to end on
    readonly property string _path: {
        const len = root._len
        if (len <= 0) return ""
        const x0 = root.thickness / 2, mid = root.height / 2, amp = root._amp
        const k = 2 * Math.PI / root._waveLength
        const shift = root._phase * 2 * Math.PI
        if (Math.abs(amp) < 0.001) return "M " + x0 + " " + mid + " H " + root._endX
        const n = Math.max(1, Math.ceil(len / (root._waveLength / 4)))
        const h = len / n
        const ramp = Math.min(root._waveLength / 2, len / 2)
        // smoothstep in from both ends, with its slope so each segment's tangents stay continuous
        const env = d => { const t = Math.max(0, Math.min(1, d / ramp)); return t * t * (3 - 2 * t) }
        const slope = d => { const t = d / ramp; return t <= 0 || t >= 1 ? 0 : 6 * t * (1 - t) / ramp }
        const taper = x => env(x) * env(len - x)
        const taperSlope = x => slope(x) * env(len - x) - env(x) * slope(len - x)
        // equal-length segments share one rotation. Carry sin and cos forward instead of evaluating them per segment
        const sinStep = Math.sin(h * k), cosStep = Math.cos(h * k)
        let sinA = Math.sin(-shift), cosA = Math.cos(-shift)
        let yA = mid, dyA = amp * (taperSlope(0) * sinA + taper(0) * k * cosA)
        const f = v => v.toFixed(3)
        let out = "M " + f(x0) + " " + f(yA)
        for (let i = 0; i < n; i++) {
            const a = i * h, b = a + h
            const sinB = sinA * cosStep + cosA * sinStep
            const cosB = cosA * cosStep - sinA * sinStep
            const yB = i === n - 1 ? mid : mid + amp * taper(b) * sinB
            const dyB = amp * (taperSlope(b) * sinB + taper(b) * k * cosB)
            out += " C " + f(x0 + a + h / 3) + " " + f(yA + dyA * h / 3)
                + " " + f(x0 + b - h / 3) + " " + f(yB - dyB * h / 3)
                + " " + f(x0 + b) + " " + f(yB)
            sinA = sinB; cosA = cosB
            yA = yB; dyA = dyB
        }
        return out
    }

    // a per-frame animation redraws the whole menu at the display rate, about 200 ms of CPU a second here; at 30 Hz a slow wave steps a third of a pixel and costs a quarter of that
    function flowAllowed(quiet: bool, reduced: bool): bool {
        return root.flowing && root.visible && root.opacity > 0.001
            && root._alpha > 0.001 && root.reveal > 0.001 && root.flowMs > 0
            && root._len > 0 && Math.abs(root._amp) >= 0.001
            && Motion.allowsMotion(quiet, reduced)
    }
    readonly property bool _flowing: root.flowAllowed(Idle.isQuiet, ShellSettings.reduceMotion)
    Timer {
        running: root._flowing
        interval: 33
        repeat: true
        onTriggered: root._flow = (root._flow + interval / root.flowMs) % 1
    }

    Rectangle {
        x: Math.min(root.width, root._trackStart - root._level * (1 - root.reveal))
        y: (root.height - root.thickness) / 2
        width: Math.max(0, root.width - x)
        height: root.thickness
        radius: root.thickness / 2
        antialiasing: true
        color: root.trackColor
        visible: width > 0.5
    }

    readonly property real _alpha: root.color.a * root.waveOpacity

    Item {
        width: root.reveal >= 1 ? root.width : root._level * root.reveal
        height: root.height
        clip: root.reveal < 1

        Shape {
            id: _shape
            readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            width: root.width
            height: root.height
            visible: root._path.length > 0
            // stroke segments overlap where they meet, so a translucent stroke beads at every joint; it draws opaque and fades as one layer
            opacity: root._alpha
            layer.enabled: root._alpha < 0.999
            transform: PixelSnap { item: _shape; dpr: _shape._dpr }
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 1)
                strokeWidth: root.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root._path }
            }
        }
    }
}
