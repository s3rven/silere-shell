pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// options stays static structure; live colours go in `colors` so palette
// changes rebind chips instead of rebuilding delegates
Item {
    id: root

    property var options: []
    property var colors: []
    property int activeIndex: -1
    property bool spread: false
    property real packSpacing: 6
    // transparent → ring follows the active chip's own colour
    property color ringColor: "transparent"
    property int hoveredIndex: -1

    signal picked(int index)

    implicitHeight: 32
    implicitWidth: options.length * 26 + Math.max(0, options.length - 1) * packSpacing

    function colorAt(i: int): color {
        return (colors && i >= 0 && i < colors.length) ? colors[i] : Theme.accent
    }

    // itemAt() is null while the repeater populates; the bump forces a re-eval
    property int _rev: 0
    readonly property var _activeSw: {
        _rev
        if (activeIndex < 0 || _rep.count <= activeIndex) return null
        return _rep.itemAt(activeIndex)
    }
    property bool _animReady: false
    Component.onCompleted: Qt.callLater(function() { root._animReady = true })

    Row {
        anchors.fill: parent
        spacing: root.spread
            ? Math.max(4, (root.width - root.options.length * 26) / Math.max(1, root.options.length - 1))
            : root.packSpacing

        Repeater {
            id: _rep
            model: root.options
            onItemAdded:   root._rev++
            onItemRemoved: root._rev++

            delegate: AccentSwatch {
                id: _sw
                required property var modelData
                required property int index
                chipColor: root.colorAt(index)
                ringColor: root.ringColor.a > 0 ? root.ringColor : chipColor
                name:      modelData.name ?? ""
                active:    index === root.activeIndex
                onPicked:  root.picked(index)
                onHoverChanged: (n, h) => {
                    if (h) root.hoveredIndex = index
                    else if (root.hoveredIndex === index) root.hoveredIndex = -1
                }

                Grid {
                    anchors.centerIn: parent
                    visible: _sw.modelData.auto === true
                    columns: 2; spacing: 2
                    Repeater {
                        model: 4
                        Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.35) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.subtext, _sw.active ? 0.45 : 0.28)
                }
            }
        }
    }

    // one ring glides between discs; freezes in place while it fades when nothing is active
    Rectangle {
        readonly property var _t: root._activeSw
        property real _frozenX: 0
        onXChanged: if (_t) _frozenX = x

        width: 30; height: 30; radius: 15
        antialiasing: true
        color: "transparent"
        border.width: 2
        border.color: root.ringColor.a > 0 ? root.ringColor
                    : _t ? _t.chipColor : root.colorAt(root.activeIndex)
        x: _t ? _t.x + (_t.width - width) / 2 : _frozenX
        y: (root.height - height) / 2
        opacity: _t ? 0.85 : 0
        visible: opacity > 0.001
        Behavior on x            { enabled: root._animReady && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
        Behavior on opacity      { NumberAnimation { duration: Motion.medium } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }
}
