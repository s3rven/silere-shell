pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"

Repeater {
    id: root

    required property Item column
    property color lineColor: Theme.menuDivider

    function present(item): bool {
        if (!item) return false
        if (item.layoutPresent !== undefined)
            return item.layoutPresent === true
        // standard card rows expose their edge or divider contract. Their animated height is presentation only and must not drive the scan
        if (item.topRadius !== undefined
                || item.suppressDividerAbove !== undefined)
            return item.visible
        return item.visible && item.height > 0.5
    }

    readonly property var _sepVisible: {
        const result = []
        const children = column ? column.children : []
        let hasAbove = false
        for (let i = 0; i < children.length; i++) {
            result.push(hasAbove)
            const c = children[i]
            if (root.present(c) && !(c.suppressDividerAbove ?? false)) hasAbove = true
        }
        return result
    }

    model: column ? column.children.length : 0
    delegate: Rectangle {
        id: _line
        required property int index
        readonly property Item row: root.column ? (root.column.children[index] ?? null) : null
        readonly property bool hasRowAbove: root._sepVisible[index] ?? false

        visible: row !== null && (row.layoutPresent ?? row.visible) && hasRowAbove
              && !(row.suppressDividerAbove ?? false) && opacity > 0.01
        x: (root.column ? root.column.x : 0) + 14
        // whole logical px, not 1/dpr: dpr is 2 while the output scale is 1.25, so a half-logical
        // grid lands on 0.625 output px and gives neighbouring dividers different weights
        y: Math.round((root.column ? root.column.y : 0) + (row ? row.y : 0))
        width: root.column
            ? Math.max(0, root.column.width - 28)
            : 0
        height: 1
        opacity: row
            ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2)
            : 0
        antialiasing: false
        color: root.lineColor
    }
}
