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
            if (!root.target || !root.target.activeFocus)
                root.pointerOwned = false
        }
    }
}
