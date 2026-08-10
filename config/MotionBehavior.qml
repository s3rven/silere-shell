import QtQuick
import "../services"

// carries the reduce-motion gate so no call site can forget it
Behavior {
    id: root

    property bool gate: true

    enabled: gate && !ShellSettings.reduceMotion

    // There used to be a settle() here that wrote targetValue through targetProperty
    // when the gate dropped, on the assumption that Qt keeps the binding. It does not:
    // that is a plain JS assignment and it destroys the binding permanently, so any
    // gate flipping mid-animation left a bound property frozen for good — a collapsed
    // bar pill never came back, and the same shape sits under the slider handle, the
    // menu rail width and the hue thumb. Measured: disabling mid-flight lets the job
    // run on to its correct target anyway, and the binding survives, so nothing needs
    // snapping. Do not reintroduce it; the declared animation's stop()/complete() does
    // not reach the Behavior's internal job either.
}
