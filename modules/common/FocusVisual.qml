import QtQuick

// QQuickItem has activeFocus, but unlike Qt Quick Controls it has no
// visualFocus property. Keep keyboard focus intact for navigation and AT while
// suppressing its ring when the same focus was acquired with a pointer.
QtObject {
    id: root

    required property Item target
    property bool pointerOwned: false
    readonly property bool active: !!root.target
        && root.target.activeFocus && !root.pointerOwned

    function takePointerFocus(): void {
        if (!root.target) return
        root.pointerOwned = true
        root.target.forceActiveFocus()
    }

    function noteKeyboardInput(): void {
        root.pointerOwned = false
    }

    property Connections _focusWatcher: Connections {
        target: root.target
        function onActiveFocusChanged(): void {
            if (!root.target || root.target.activeFocus) return
            // Qt drops focus when an item is disabled and restores it on re-enable. A row that
            // disables itself while its own click is being handled would come back looking
            // keyboard-focused, so pointer ownership has to survive that round trip.
            if (!root.target.enabled) return
            root.pointerOwned = false
        }
    }
}
