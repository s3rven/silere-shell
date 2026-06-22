pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Rounded card with auto-separators. Draws a 1px divider above each visible,
// non-zero-height child, skips collapsed rows so no stray lines appear.
Rectangle {
    id: root

    default property alias rows: col.data
    property color rowDivider: Theme.menuDivider
    // 12 to match every row's content inset (glyphs sit at leftMargin 12) so a
    // divider starts directly under the glyph column instead of 2px inboard.
    readonly property real _dividerInset: Math.min(12, Math.max(0, width / 2))

    width:  parent ? parent.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight
    radius: Theme.radiusControl
    antialiasing: true
    clip: true
    color: Theme.menuCard
    border.width: 1
    border.color: Theme.menuCardBorder

    Column {
        id: col
        width: parent.width
        spacing: 0
    }

    readonly property var _sepVisible: {
        const result = []
        const children = col.children
        let hasAbove = false
        for (let i = 0; i < children.length; i++) {
            result.push(hasAbove)
            const c = children[i]
            if (c && c.visible && c.height > 0.5) hasAbove = true
        }
        return result
    }

    Repeater {
        model: root.visible ? col.children.length : 0
        delegate: Rectangle {
            required property int index
            readonly property Item row: col.children[index] ?? null

            readonly property bool hasRowAbove: root._sepVisible[index] ?? false

            visible: row !== null && row.visible && hasRowAbove
                  && !(row.suppressDividerAbove ?? false) && opacity > 0.01
            x: root._dividerInset
            // Row heights and panel offsets sit on the 4px grid (see
            // fractional-scaling notes), so row.y lands on whole physical px
            // and every divider renders the same thickness.
            y: row ? Math.round(row.y) : 0
            width:  Math.max(0, root.width - root._dividerInset * 2)
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
