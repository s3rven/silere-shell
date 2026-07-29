pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../../config"

Repeater {
    id: root

    required property Item column
    property color lineColor: Theme.menuDivider
    property int horizontalInset: 14
    readonly property real _dpr: Math.max(1, Screen.devicePixelRatio)
    readonly property real _hairline: 1 / _dpr

    readonly property var _sepVisible: {
        const result = []
        const children = column ? column.children : []
        let hasAbove = false
        for (let i = 0; i < children.length; i++) {
            result.push(hasAbove)
            const c = children[i]
            if (c && c.visible && c.height > 0.5 && !(c.suppressDividerAbove ?? false)) hasAbove = true
        }
        return result
    }

    model: column ? column.children.length : 0
    delegate: Item {
        id: _line
        required property int index
        readonly property Item row: root.column ? (root.column.children[index] ?? null) : null
        readonly property bool hasRowAbove: root._sepVisible[index] ?? false

        visible: row !== null && row.visible && hasRowAbove
              && !(row.suppressDividerAbove ?? false) && opacity > 0.01
        x: (root.column ? root.column.x : 0) + root.horizontalInset
        // rows sit on the 4px grid; snap the leftover local offset so every
        // divider lands on the same physical pixel at fractional scales
        y: Math.round(((root.column ? root.column.y : 0)
            + (row ? row.y : 0)) * root._dpr) / root._dpr
        width: root.column
            ? Math.max(0, root.column.width - root.horizontalInset * 2)
            : 0
        height: root._hairline
        opacity: row
            ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2)
            : 0

        Rectangle {
            anchors.fill: parent
            antialiasing: false
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.10; color: root.lineColor }
                GradientStop { position: 0.90; color: root.lineColor }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
