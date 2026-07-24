import QtQuick

SequentialAnimation {
    id: pulse

    property var    target
    property string targetProperty
    property real   peak:      1.0
    property real   floor:     0.0
    property int    duration:  2000
    property real   restValue: 0.0

    loops: Animation.Infinite
    onRunningChanged: if (!running && target && targetProperty) target[targetProperty] = restValue
    onDurationChanged: if (running) restart()

    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.peak;  duration: pulse.duration; easing.type: Easing.InOutSine }
    NumberAnimation { target: pulse.target; property: pulse.targetProperty; to: pulse.floor; duration: pulse.duration; easing.type: Easing.InOutSine }
}
