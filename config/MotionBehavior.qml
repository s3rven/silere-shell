import QtQuick
import "../services"

// carries the reduce-motion gate so no call site can forget it
Behavior {
    id: root

    property bool gate: true

    enabled: gate && !ShellSettings.reduceMotion

    // Disabling a Behavior prevents new jobs but does not cancel one that is
    // already running. Snap it so close/drag/reduce-motion gates really
    // mean "settled now" instead of allowing residual drift.
    function settle(): void {
        // Behavior runs an internal animation job; the declared animation's
        // running/stop/complete state does not control that job. Writing the
        // pending target through targetProperty both snaps and cancels it,
        // while Qt preserves an existing binding on the animated property.
        const property = root.targetProperty
        if (!property || !property.object || !property.name
                || root.targetValue === undefined) return
        property.object[property.name] = root.targetValue
    }

    onEnabledChanged: if (!enabled) root.settle()
}
