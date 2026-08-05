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

    running: active && !ShellSettings.reduceMotion && duration > 0
    loops: Animation.Infinite
    onRunningChanged: if (!running && target && targetProperty) target[targetProperty] = restValue
    onDurationChanged: if (running) restart()

    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.peak;  duration: pulse.duration; easing.type: Easing.InOutSine }
    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.floor; duration: pulse.duration; easing.type: Easing.InOutSine }
}
