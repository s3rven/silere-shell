pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Rounded card with auto-separators. Draws a 1px divider above each visible,
// non-zero-height child, skips collapsed rows so no stray lines appear.
Rectangle {
    id: root

    default property alias rows: col.data
    property color rowDivider: Theme.menuDivider

    width:  parent ? parent.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight
    radius: Theme.radiusControl
    antialiasing: true
    color: Theme.menuCard
    border.width: 1
    border.color: Theme.menuCardBorder

    Column {
        id: col
        width: parent.width
        spacing: 0
    }

    Repeater {
        model: col.children.length
        delegate: Rectangle {
            required property int index
            readonly property Item row: col.children[index] ?? null

            // separator only above a row that has a visible row before it
            readonly property bool hasRowAbove: {
                for (let i = 0; i < index; i++) {
                    const c = col.children[i]
                    if (c && c.visible && c.height > 0.5) return true
                }
                return false
            }

            visible: row !== null && row.visible && hasRowAbove
                  && !(row.suppressDividerAbove ?? false) && opacity > 0.01
            x: 14
            // Row heights and panel offsets sit on the 4px grid (see
            // fractional-scaling notes), so row.y lands on whole physical px
            // and every divider renders the same thickness.
            y: row ? Math.round(row.y) : 0
            width:  root.width - 28
            height: 1
            // Hairline: skip antialiasing (smears a 1px line at 1.25x rather than
            // sharpening it) and keep the colour faint so even a 2px-rounded
            // physical line reads as a fine seam, not a bar.
            antialiasing: false
            color:  root.rowDivider
            // Fade with the row's reveal: a collapsible expanding from 0 grows its
            // divider in over the first ~20px instead of popping a hard line, and
            // a faded-out row (opacity ≤ ~0) takes its divider with it.
            opacity: row
                ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2)
                : 0
        }
    }
}
