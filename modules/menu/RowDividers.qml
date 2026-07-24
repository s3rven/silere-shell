pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Repeater {
    id: root

    required property Item column
    property color lineColor: Theme.menuDivider

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
    delegate: Rectangle {
        id: _line
        required property int index
        readonly property Item row: root.column ? (root.column.children[index] ?? null) : null
        readonly property bool hasRowAbove: root._sepVisible[index] ?? false

        visible: row !== null && row.visible && hasRowAbove
              && !(row.suppressDividerAbove ?? false) && opacity > 0.01
        x: (root.column ? root.column.x : 0) + 12
        // Row heights and panel offsets sit on the 4px grid (see fractional-scaling
        // notes), so row.y lands on whole physical px and every divider renders the
        // same thickness. `column.y` also supports any intentionally offset group.
        y: (root.column ? root.column.y : 0) + (row ? Math.round(row.y) : 0)
        width:  root.column ? Math.max(0, root.column.width - 24) : 0
        height: 1
        // Hairline: skip antialiasing (smears a 1px line at 1.25x). A faint colour
        // keeps even a 2px-rounded physical line reading as a fine seam.
        antialiasing: false
        color: root.lineColor
        opacity: row
            ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2)
            : 0
    }
}
