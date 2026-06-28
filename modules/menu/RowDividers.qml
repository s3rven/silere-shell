pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Auto 1px separators above each visible, non-collapsed child of `column`. One
// rule shared by SettingsCard and CollapsibleSection, so rows nested in a
// collapsible get the same seams as flat ones. Place as an overlay sibling of
// `column` (positions are taken relative to it, including its live y).
Repeater {
    id: root

    required property Item column
    property color lineColor: Theme.menuDivider
    property real  inset:     12
    // Each end eases out over this many px instead of stopping at a hard 1px wall.
    property real  fadePx:    26

    // 12 matches every row's content inset (glyphs sit at leftMargin 12) so a
    // divider starts under the glyph column, never wider than the card allows.
    readonly property real _inset: Math.min(inset, Math.max(0, (column ? column.width : 0) / 2))

    readonly property var _sepVisible: {
        const result = []
        const children = column ? column.children : []
        let hasAbove = false
        for (let i = 0; i < children.length; i++) {
            result.push(hasAbove)
            const c = children[i]
            // A divider-transparent element (a HintText, or a collapsible that opens
            // with one) neither takes a line above nor induces one below, so an
            // annotation never gets fenced off from the control it explains.
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
        x: root._inset
        // Row heights and panel offsets sit on the 4px grid (see fractional-scaling
        // notes), so row.y lands on whole physical px and every divider renders the
        // same thickness. `column.y` folds in a collapsible's animating offset.
        y: (root.column ? root.column.y : 0) + (row ? Math.round(row.y) : 0)
        width:  Math.max(0, (root.column ? root.column.width : 0) - root._inset * 2)
        height: 1
        // Hairline: skip antialiasing (smears a 1px line at 1.25x). A faint colour
        // keeps even a 2px-rounded physical line reading as a fine seam.
        antialiasing: false
        readonly property real _fade: width > 0 ? Math.min(0.45, root.fadePx / width) : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;             color: Theme.withAlpha(root.lineColor, 0) }
            GradientStop { position: _line._fade;     color: root.lineColor }
            GradientStop { position: 1 - _line._fade; color: root.lineColor }
            GradientStop { position: 1.0;             color: Theme.withAlpha(root.lineColor, 0) }
        }
        // Fade with the row's reveal: a collapsible growing from 0 grows its divider
        // in over the first ~20px instead of popping, and a faded row takes it along.
        opacity: row
            ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2)
            : 0
    }
}
