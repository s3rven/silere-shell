import QtQuick
import "../services"

MotionBehavior {
    id: root

    // a colour that changes beside a slower motion keeps that motion's pace
    property int duration: Motion.color
    // read from the palette's targets, not its eased colours, as a swatch is: nothing eases it during a shift
    property bool rawSource: false

    // while the palette itself is easing, the source colour behind this one is already
    // moving: fading again double-eases it and restarts on every frame of the shift
    enabled: gate && !ShellSettings.reduceMotion && !Idle.isIdle && (rawSource || !Theme.paletteShifting) && !Motion.unseen

    ColorAnimation { duration: root.duration }
}
