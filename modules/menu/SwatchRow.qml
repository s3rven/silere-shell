pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    property var options: []
    property var colors: []
    property int activeIndex: -1
    property bool spread: false
    property real packSpacing: 6
    property int edgePadding: 4
    property color ringColor: "transparent"
    property int hoveredIndex: -1
    property string groupLabel: ""

    signal picked(int index)
    signal focusMoved(int index)

    implicitHeight: 32
    implicitWidth: edgePadding * 2 + options.length * 26
        + Math.max(0, options.length - 1) * packSpacing

    function colorAt(i: int): color {
        return (colors && i >= 0 && i < colors.length) ? colors[i] : Theme.accent
    }

    function itemLeft(i: int): real {
        root._rev
        const item = i >= 0 && i < _rep.count ? _rep.itemAt(i) : null
        return item ? _chipRow.x + item.x : 0
    }

    function itemRight(i: int): real {
        root._rev
        const item = i >= 0 && i < _rep.count ? _rep.itemAt(i) : null
        return item ? _chipRow.x + item.x + item.width : 0
    }

    // itemAt() is null while the repeater populates; the bump forces a re-eval
    property int _rev: 0
    Row {
        id: _chipRow
        x: root.edgePadding
        width: Math.max(0, parent.width - root.edgePadding * 2)
        height: parent.height
        spacing: root.spread
            ? Math.max(4, (width - root.options.length * 26) / Math.max(1, root.options.length - 1))
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
                groupLabel: root.groupLabel
                active:    index === root.activeIndex
                onPicked:  root.picked(index)
                onHoverChanged: (n, h) => {
                    if (h) root.hoveredIndex = index
                    else if (root.hoveredIndex === index) root.hoveredIndex = -1
                }
                onActiveFocusChanged: if (activeFocus) root.focusMoved(index)
                Keys.onLeftPressed: event => {
                    const it = _rep.itemAt(_sw.index - 1)
                    if (it) it.forceActiveFocus()
                    event.accepted = true
                }
                Keys.onRightPressed: event => {
                    const it = _rep.itemAt(_sw.index + 1)
                    if (it) it.forceActiveFocus()
                    event.accepted = true
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
                    anchors.centerIn: parent
                    width: _sw.active ? 28 : 22
                    height: width
                    radius: width / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: _sw.active ? 2 : 1
                    border.color: _sw.active
                        ? (root.ringColor.a > 0
                            ? root.ringColor
                            : Theme.mix(_sw.chipColor, Theme.text, 0.68))
                        : Theme.withAlpha(Theme.subtext, 0.24)
                }
            }
        }
    }
}
