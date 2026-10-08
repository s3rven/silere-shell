import QtQuick
import "../services"

// A critically damped glide keeps velocity when its destination moves. Advance
// analytically per frame so panel reflow cannot restart the easing clock.
QtObject {
    id: root

    required property real target
    property real value: 0
    property int duration: Motion.panelResize
    // Geometry is measured in pixels; selection slots need a finer tolerance.
    property real precision: 0.1
    property bool gate: true
    property real _velocity: 0
    readonly property bool running: _tick.running
    readonly property bool _motionAllowed: root.gate && root.duration > 0
        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)

    function _snap(): void {
        _tick.running = false
        root._velocity = 0
        root.value = root.target
    }

    function _advance(seconds: real): void {
        if (!root._motionAllowed) { root._snap(); return }
        // Limit catch-up after a blocked frame; the first rendered step should
        // still be part of the glide rather than a jump to its end.
        const dt = Math.max(0, Math.min(seconds, 0.05))
        if (dt === 0) return
        const omega = 8 / (root.duration / 1000)
        const offset = root.value - root.target
        const carry = root._velocity + omega * offset
        const decay = Math.exp(-omega * dt)
        const next = root.target + (offset + carry * dt) * decay
        const velocity = (root._velocity - omega * carry * dt) * decay
        // A retarget can leave velocity pointing past the new destination.
        // Stop on crossing it, so a resizing panel never bounces through it.
        if ((next - root.target) * offset <= 0
                || (Math.abs(next - root.target) < root.precision
                    && Math.abs(velocity) < root.precision * 10)) {
            root._snap()
            return
        }
        root._velocity = velocity
        root.value = next
    }

    onTargetChanged: {
        if (root._motionAllowed) _tick.running = true
        else root._snap()
    }
    on_MotionAllowedChanged: if (!root._motionAllowed) root._snap()
    Component.onCompleted: root._snap()

    property FrameAnimation _tick: FrameAnimation {
        running: false
        onTriggered: root._advance(frameTime)
    }
}
