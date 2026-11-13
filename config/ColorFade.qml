import QtQuick
import "../services"

MotionBehavior {
    id: root

    // a colour that changes beside a slower motion keeps that motion's pace
    property int duration: Motion.color

    // while the palette itself is easing, the source colour behind this one is already
    // moving: fading again double-eases it and restarts on every frame of the shift
    enabled: gate && !ShellSettings.reduceMotion && !Idle.isIdle && !Theme.paletteShifting

    ColorAnimation { duration: root.duration }
}
