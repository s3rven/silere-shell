import QtQuick
import "../services"

// carries the reduce-motion and blanked-screen gates so no call site can forget them
Behavior {
    id: root

    property bool gate: true

    enabled: gate && !ShellSettings.reduceMotion && !Idle.isIdle

    // branch timings on targetValue: a flag-bound duration updates only after the job starts

    // never add a settle() that writes targetValue through targetProperty: that plain JS
    // assignment destroys the binding for good, and a gate flipping mid-animation then freezes
    // the property. Measured: disabling mid-flight reaches the target anyway, binding intact.
}
