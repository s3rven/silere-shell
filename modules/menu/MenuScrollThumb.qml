import QtQuick
import "../../config"
import "../../services"

Rectangle {
    id: root

    required property Flickable list
    property bool shown: true
    property int trackInset: 8
    property int rightInset: 3
    property int minimumLength: 22
    property real idleOpacity: 0.26
    property real movingOpacity: 0.62

    // the panel animates its height on every page/section swap, so overflow is
    // transiently true mid-resize; settle it or the thumb blinks on each switch
    readonly property bool _overflows: list.contentHeight > list.height + 1
    property bool _settled: false
    function _syncSettle(): void {
        if (!root._overflows || !root.shown || !root.list.visible) {
            _settle.stop()
            root._settled = false
            return
        }
        _settle.restart()
    }
    on_OverflowsChanged: _syncSettle()
    onShownChanged: _syncSettle()
    Connections {
        target: root.list
        function onVisibleChanged() { root._syncSettle() }
    }
    Timer {
        id: _settle
        interval: Motion.panelHeight
        onTriggered: root._settled = root.shown && root.list.visible && root._overflows
    }
    // a list built already overflowing never emits the change signal above
    Component.onCompleted: _syncSettle()

    readonly property real _trackH: Math.max(1,
        list.height - trackInset * 2)
    readonly property real _overflow: Math.max(1,
        list.contentHeight - list.height)
    readonly property real _position: Math.max(0, Math.min(1,
        list.contentY / _overflow))

    x: list.x + list.width - rightInset - width
    y: list.y + trackInset + Math.max(0, _trackH - height) * _position
    width: 2
    height: Math.min(_trackH, Math.max(minimumLength,
        _trackH * Math.min(1, list.height / Math.max(1, list.contentHeight))))
    radius: 1
    antialiasing: true
    color: Theme.accent
    opacity: visible ? (list.moving ? movingOpacity : idleOpacity) : 0
    visible: shown && list.visible && root._settled

    Behavior on opacity {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.fast }
    }
}
