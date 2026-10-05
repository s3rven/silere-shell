import QtQuick
import "../services"

// SpringAnimation steps in 16 ms ticks (Qt caps it at 62 fps): on a 240 Hz panel a glide moved one frame in four;
// this runs the same law, v += spring*d - damping*v per 16 ms, every frame, and stops within a fifth of a px
QtObject {
    id: root

    required property real target
    property real value: 0
    property bool gate: true
    property real spring: 4.4
    property real damping: 0.62

    property real _velocity: 0
    readonly property bool _moving: root.gate && !ShellSettings.reduceMotion && !Idle.isIdle

    function _snap(): void {
        _tick.running = false
        root._velocity = 0
        root.value = root.target
    }

    onTargetChanged: {
        if (root._moving) _tick.running = true
        else root._snap()
    }
    on_MovingChanged: if (!root._moving) root._snap()
    Component.onCompleted: root.value = root.target

    property FrameAnimation _tick: FrameAnimation {
        running: false
        onTriggered: {
            // a slow frame still integrates in small steps, or the spring overshoots on catch-up
            const span = Math.min(frameTime, 0.05)
            const steps = Math.max(1, Math.ceil(span / 0.004))
            const h = span / steps
            let x = root.value
            let v = root._velocity
            for (let i = 0; i < steps; i++) {
                v += (root.spring * (root.target - x) - root.damping * v) / 0.016 * h
                x += v * h
            }
            root._velocity = v
            if (Math.abs(root.target - x) < 0.005 && Math.abs(v) < 0.05) root._snap()
            else root.value = x
        }
    }
}
