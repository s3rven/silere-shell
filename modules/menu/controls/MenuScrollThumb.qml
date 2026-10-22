import QtQuick
import "../../../config"
import "../../common"

Rectangle {
    id: root

    required property Flickable list
    property bool shown: true
    property int trackInset: 8
    property int rightInset: 3
    property int minimumLength: 22
    property real idleOpacity: 0.26
    property real movingOpacity: 0.62
    property real fadeMultiplier: 1.0
    property string contextKey: ""
    readonly property bool dragging: root._dragging
    readonly property bool _canInteract: root.enabled && root.visible && root.shown
        && root.list.enabled && root.list.interactive && root.fadeMultiplier > 0.001
    property bool _dragging: false
    property real _grabRatio: 0
    property real _pointerY: 0

    function _press(parentY: real): void {
        if (!root._canInteract) return
        root.list.cancelFlick()
        root._grabRatio = Math.max(0, Math.min(1, (parentY - root.y) / root.height))
        root._pointerY = parentY
        root._dragging = true
    }

    function _drag(parentY: real): void {
        root._pointerY = parentY
        root._applyDrag()
    }

    function _applyDrag(): void {
        if (!root._dragging || !root._canInteract) return
        const travel = root._trackH - root.height
        if (travel <= 0) return
        const ratio = Math.max(0, Math.min(1,
            (root._pointerY - root._grabRatio * root.height
                - root.list.y - root.trackInset) / travel))
        const next = root.list.originY + ratio * root._overflow
        if (Math.abs(root.list.contentY - next) > 0.01) root.list.contentY = next
    }

    function _cancel(): void { root._dragging = false }

    on_CanInteractChanged: if (!root._canInteract) root._cancel()
    onListChanged: root._cancel()
    onContextKeyChanged: root._cancel()
    onTrackInsetChanged: root._cancel()
    Connections {
        target: root.list
        // virtualized lists revise their range as new rows are measured
        function onContentHeightChanged() {
            if (root.dragging) Qt.callLater(root._applyDrag)
        }
        function onOriginYChanged() {
            if (root.dragging) Qt.callLater(root._applyDrag)
        }
        function onHeightChanged() { root._cancel() }
    }

    ScrollSettle {
        id: _settle
        list: root.list
        armed: root.shown
        contextKey: root.contextKey
    }

    readonly property real _trackH: Math.max(1,
        list.height - trackInset * 2)
    readonly property real _overflow: Math.max(1,
        list.contentHeight - list.height)
    readonly property real _position: Math.max(0, Math.min(1,
        (list.contentY - list.originY) / _overflow))

    x: list.x + list.width - rightInset - width
    y: list.y + trackInset + Math.max(0, _trackH - height) * _position
    width: root.dragging || _mouse.containsMouse ? 4 : 2
    height: Math.min(_trackH, Math.max(minimumLength,
        _trackH * Math.min(1, list.height / Math.max(1, list.contentHeight))))
    radius: 1
    antialiasing: true
    color: Theme.accent
    opacity: (visible ? (root.dragging || _mouse.containsMouse ? 1
        : list.moving ? movingOpacity : idleOpacity) : 0) * root.fadeMultiplier
    visible: _settle.ready

    // keep the visual line slim while allowing a grab from the menu's gutter
    // map into the parent: the thumb itself moves beneath the held pointer
    MouseArea {
        id: _mouse
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 14
        enabled: root._canInteract
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => root._press(mapToItem(root.parent, mouse.x, mouse.y).y)
        onPositionChanged: mouse => {
            if (pressed) root._drag(mapToItem(root.parent, mouse.x, mouse.y).y)
        }
        onReleased: root._cancel()
        onCanceled: root._cancel()
        onWheel: wheel => wheel.accepted = false
    }

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }
}
