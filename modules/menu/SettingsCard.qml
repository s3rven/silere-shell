pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../common"

Rectangle {
    id: root

    default property alias rows: col.data
    property color rowDivider: Theme.menuDivider
    property bool showBorder: true

    width:  parent ? parent.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight
    radius: Theme.radiusCard
    antialiasing: true
    clip: true
    color: Theme.menuCard

    OutlineBorder {
        radius: root.radius
        outlineColor: root.showBorder ? Theme.menuCardBorder : "transparent"
    }

    Column {
        id: col
        width: parent.width
        spacing: 0
    }

    RowDividers { column: col; lineColor: root.rowDivider }

    function _edgeEl(container, first): var {
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
    function _applyRows(container, leftOffset, first, last) {
        const baseX = leftOffset ?? 0
        const ch = container.children
        for (let i = 0; i < ch.length; i++) {
            const c = ch[i]
            if (!c) continue
            const childX = baseX + Math.max(0, Number(c.x) || 0)
            if (c.isRadiusGroup === true && c.radiusColumn) {
                const contentX = childX
                    + Math.max(0, Number(c.radiusColumn.x) || 0)
                root._applyRows(c.radiusColumn, contentX, first, last)
                continue
            }
            if (c.topRadius === undefined || c.bottomRadius === undefined) continue

            const bleed = Math.round(childX)
            const top = c === first ? root.radius : 0
            const bottom = c === last ? root.radius : 0
            if (c.cardLeftBleed !== undefined && c.cardLeftBleed !== bleed)
                c.cardLeftBleed = bleed
            if (c.topRadius !== top) c.topRadius = top
            if (c.bottomRadius !== bottom) c.bottomRadius = bottom
        }
    }

    function _applyRadii() {
        const fe = root._edgeEl(col, true)
        const le = root._edgeEl(col, false)
        root._applyRows(col, 0, fe, le)
    }

    // re-derive when the row set could change. height moves on the obvious edits (collapsible opening, row hiding),
    // but a Column keeps counting hidden children — a card in an unshown section stays full-height, so navigating
    // to it flips visible without changing implicitHeight; visibleChanged catches that.
    // zero-interval timer, not Qt.callLater: it coalesces the same way but dies with the card, where a
    // deferred callLater on a card torn down by a section swap fires in a dead context and warns
    Timer { id: _radiiDefer; interval: 0; onTriggered: root._applyRadii() }
    onImplicitHeightChanged: _radiiDefer.restart()
    onVisibleChanged:        _radiiDefer.restart()
    Component.onCompleted:   root._applyRadii()
}
