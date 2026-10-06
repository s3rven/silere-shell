pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../common"

Item {
    id: root

    property var options: []
    property var colors: []
    property int activeIndex: -1
    property bool outlined: false
    property bool spread: false
    property int edgePadding: 4
    property color ringColor: "transparent"
    property int hoveredIndex: -1
    property string accessiblePrefix: ""

    onOptionsChanged: if (root.hoveredIndex >= root.options.length)
        root.hoveredIndex = -1

    signal picked(int index)

    implicitHeight: Metrics.rowHeightFor(32)
    implicitWidth: edgePadding * 2 + options.length * 26
        + Math.max(0, options.length - 1) * 6

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
            : 6

        Repeater {
            id: _rep
            model: root.options
            onItemAdded:   root._rev++
            onItemRemoved: root._rev++

            delegate: AccentSwatch {
                id: _sw
                required property var modelData
                required property int index
                // on the row's centre, unrounded, like the ring: rounding either one alone set the chip a device pixel off it
                y: (_chipRow.height - height) / 2
                chipColor: root.colorAt(index)
                name:      modelData.name ?? ""
                accessiblePrefix: root.accessiblePrefix
                spectrum:  modelData.spectrum === true
                outlined:  root.outlined
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
            }
        }
    }

    // travels by slot, not pixels: a relayout moves it with the swatches instead of chasing them
    property real _slotTarget: Math.max(0, root.activeIndex)
    onActiveIndexChanged: if (root.activeIndex >= 0) root._slotTarget = root.activeIndex
    readonly property real _slot: _slotGlide.value
    SpringGlide { id: _slotGlide; target: root._slotTarget }

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    Rectangle {
        id: _selection
        // the chip plus a whole-device-pixel gap each side: an odd difference cannot centre on the grid
        width: Metrics.devicePx(22, root._dpr) + 2 * Metrics.devicePx(3, root._dpr)
        height: width
        transform: PixelSnap { item: _selection; dpr: root._dpr }
        radius: width / 2
        antialiasing: true
        color: "transparent"
        x: _chipRow.x + root._slot * (26 + _chipRow.spacing) + 13 - width / 2
        y: (root.height - height) / 2
        opacity: root.activeIndex >= 0 ? 1 : 0
        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }

        // the chosen colour itself, not a whitened mix of it: on an accent row that is the accent, which a row of dark swatches passes as ringColor, so every swatch row marks its choice alike
        OutlineBorder {
            radius: _selection.radius
            outlineWidth: 2
            outlineColor: root.ringColor.a > 0 ? root.ringColor : root.colorAt(root.activeIndex)
            ColorFade on outlineColor {}
        }
    }
}
