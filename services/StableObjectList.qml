pragma ComponentBehavior: Bound

import QtQuick

// hold one model snapshot while its members and order remain unchanged. Object
// properties still notify their bindings without resetting every list delegate
QtObject {
    id: root

    property var source: []
    property var _values: []
    readonly property alias values: root._values

    function sync(): void {
        // QML can expose a QVariantList as an array-like sequence rather than a JavaScript Array, including initial properties in createObject()
        const next = root.source && typeof root.source.slice === "function" ? root.source : []
        const current = root._values
        if (next.length === current.length
                && next.every((item, index) => item === current[index])) return
        // own the array so a caller's in-place mutation cannot silently change the published model before its next synchronization
        root._values = next.slice()
    }

    onSourceChanged: root.sync()
    Component.onCompleted: root.sync()
}
