import QtQuick
import "../services"

// carries the reduce-motion gate so no call site can forget it
Behavior {
    id: root

    property bool gate: true

    enabled: gate && !ShellSettings.reduceMotion

    // never add a settle() that writes targetValue through targetProperty: that plain JS
    // assignment destroys the binding for good, and a gate flipping mid-animation then freezes
    // the property. Measured: disabling mid-flight reaches the target anyway, binding intact.
}
