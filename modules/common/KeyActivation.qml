pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property bool enabled: true
    property QtObject focusVisual: null
    signal activated()

    readonly property bool pressed: _held
    property bool _held: false

    function _isActivationKey(key): bool {
        return key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter
    }

    function cancel(): void {
        root._held = false
    }

    function press(event): void {
        if (root.focusVisual) root.focusVisual.noteKeyboardInput()
        if (!root.enabled || !root._isActivationKey(event.key)) return
        event.accepted = true
        // a held key repeats press events; the first one owns the activation
        if (event.isAutoRepeat) return
        root._held = true
    }

    function release(event): void {
        if (!root._held || !root._isActivationKey(event.key)) return
        event.accepted = true
        // auto-repeat releases arrive while the key is still down
        if (event.isAutoRepeat) return
        root._held = false
        root.activated()
    }
}
