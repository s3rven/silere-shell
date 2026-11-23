import QtQuick
import "../services"

// carries the reduce-motion gate so no call site can forget it; a 0-duration infinite loop would spin instead of resting
SequentialAnimation {
    id: pulse

    property var    target
    property string targetProperty
    property real   peak:      1.0
    property real   floor:     0.0
    property int    duration:  2000
    property real   restValue: 0.0
    property bool   active:    false

    running: active && !ShellSettings.reduceMotion && !Motion.unseen && duration > 0
    loops: Animation.Infinite
    // an alert that settles or clears stops mid-swing: set at once, its glow or dim jumped back to rest in one frame by up
    // to its whole range, so it eases there at the pulse's own pace. Unseen, without motion or without a duration it rests at once
    onRunningChanged: {
        if (running) {
            _settle.stop()
            return
        }
        if (!target || !targetProperty) return
        const from = Number(target[targetProperty])
        const span = Math.abs(peak - floor)
        const ms = span > 0 && isFinite(from)
            ? Math.round(duration * Math.min(1, Math.abs(from - restValue) / span)) : 0
        if (ms > 0 && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)) {
            _settle.duration = ms
            _settle.restart()
        } else {
            target[targetProperty] = restValue
        }
    }
    property NumberAnimation _settle: NumberAnimation {
        target: pulse.target; property: pulse.targetProperty; to: pulse.restValue
        // leaves with the swing's speed rather than from a standstill
        easing.type: Easing.OutSine
    }
    onDurationChanged: {
        // duration reaches zero a binding update before running observes it
        if (duration <= 0 || ShellSettings.reduceMotion) {
            if (running) stop()
        } else if (running) {
            restart()
        }
    }

    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.peak;  duration: pulse.duration; easing.type: Easing.InOutSine }
    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.floor; duration: pulse.duration; easing.type: Easing.InOutSine }
}
