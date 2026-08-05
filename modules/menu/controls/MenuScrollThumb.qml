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

    ScrollSettle {
        id: _settle
        list: root.list
        armed: root.shown
    }

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
    opacity: (visible ? (list.moving ? movingOpacity : idleOpacity) : 0) * root.fadeMultiplier
    visible: _settle.ready

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }
}
