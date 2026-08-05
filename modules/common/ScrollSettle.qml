import QtQuick
import "../../config"

Item {
    id: root

    required property Flickable list
    property bool armed: true

    readonly property bool overflows: list.contentHeight > list.height + 1
    readonly property bool ready: armed && list.visible && overflows && _settled

    property bool _settled: false

    function sync(): void {
        if (!root.armed || !root.overflows || !root.list.visible) {
            _quiet.stop()
            root._settled = false
            return
        }
        // once earned, keep it: a media card or section expanding mid-scroll must not blink the affordance out
        if (root._settled) return
        _quiet.restart()
    }

    onOverflowsChanged: sync()
    onArmedChanged: sync()

    // a resizing viewport reads as overflowing for the whole animation; wait out the geometry, not a fixed delay
    Connections {
        target: root.list
        function onVisibleChanged() { root.sync() }
        function onHeightChanged() { root.sync() }
        function onContentHeightChanged() { root.sync() }
    }

    Timer {
        id: _quiet
        interval: Motion.panelSettle
        onTriggered: root._settled = root.armed && root.list.visible && root.overflows
    }

    // a list built already overflowing never emits the change signals above
    Component.onCompleted: sync()
}
