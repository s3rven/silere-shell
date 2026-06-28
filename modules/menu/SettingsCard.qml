pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Rounded card with auto-separators and auto corner-rounding. Rows never set
// their own divider or radius: the card derives both from layout, so a row can't
// guess wrong about its position (e.g. a middle row rounding its hover fill, or a
// hidden neighbour leaving a stray line). Recurses into CollapsibleSections so
// nested rows are treated exactly like flat ones.
Rectangle {
    id: root

    default property alias rows: col.data
    property color rowDivider: Theme.menuDivider

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

    RowDividers { column: col; lineColor: root.rowDivider }

    // ── Auto corner-rounding ────────────────────────────────────────────────
    function _edgeEl(container, first) {
        const ch = container.children
        const end  = first ? ch.length : -1
        const step = first ? 1 : -1
        for (let i = first ? 0 : ch.length - 1; i !== end; i += step) {
            const c = ch[i]
            if (!c || !c.visible || !(c.height > 0.5)) continue
            if (c.isRadiusGroup === true && c.radiusColumn) {
                const inner = root._edgeEl(c.radiusColumn, first)
                if (inner) return inner
                continue
            }
            return c
        }
        return null
    }
    function _collectRows(container, out) {
        const ch = container.children
        for (let i = 0; i < ch.length; i++) {
            const c = ch[i]
            if (!c) continue
            if (c.isRadiusGroup === true && c.radiusColumn) { root._collectRows(c.radiusColumn, out); continue }
            if (c.topRadius !== undefined && c.bottomRadius !== undefined) out.push(c)
        }
    }

    // cache edges: implicitHeight fires every frame during expand, but edges rarely change
    property var _cachedFirst: null
    property var _cachedLast:  null

    function _applyRadii() {
        const fe = root._edgeEl(col, true)
        const le = root._edgeEl(col, false)
        if (fe === root._cachedFirst && le === root._cachedLast) return
        root._cachedFirst = fe
        root._cachedLast  = le
        const rows = []
        root._collectRows(col, rows)
        for (let i = 0; i < rows.length; i++) {
            rows[i].topRadius    = (rows[i] === fe) ? root.radius : 0
            rows[i].bottomRadius = (rows[i] === le) ? root.radius : 0
        }
    }

    // Re-derive when the row set could have changed. Height moves on the obvious
    // edits (a collapsible opening, a row hiding). But a Column keeps counting its
    // hidden children, so a card in an unshown settings section sits at full height
    // the whole time — navigating to it flips the card visible without ever
    // changing implicitHeight, so visibleChanged is what catches that. callLater
    // coalesces both to one run per frame; no polling, no per-frame allocation.
    onImplicitHeightChanged: Qt.callLater(root._applyRadii)
    onVisibleChanged:        Qt.callLater(root._applyRadii)
    Component.onCompleted:   root._applyRadii()
}
