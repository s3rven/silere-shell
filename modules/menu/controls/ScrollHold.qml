import QtQuick
import "../../../config"

QtObject {
    id: root

    property Item item: null
    property Item watched: null
    property real _y: NaN
    property bool _opening: false
    readonly property bool leads: root._opening && isFinite(root._y)

    // call before content above `item` starts to grow or shrink. One hold scrolls a page at a time: two rows
    // cannot both stay put while the space between them changes, and the one opening is under the pointer
    function arm(opening: bool): void {
        if (!root.item) return
        const view = root._viewport()
        if (view && view.moving) return
        if (view && view.scrollHold !== undefined) {
            const other = view.scrollHold
            if (!opening && other && other !== root && other.leads) return
            view.scrollHold = root
        }
        root._opening = opening
        root._y = root.item.mapToItem(null, 0, 0).y
        root._release.restart()
    }

    function release(): void {
        root._y = NaN
        root._release.stop()
        const view = root._viewport()
        if (view && view.scrollHold === root) view.scrollHold = null
    }

    function _viewport(): var {
        for (let p = root.item ? root.item.parent : null; p; p = p.parent)
            if (p.contentY !== undefined && p.contentItem && p.height > 0) return p
        return null
    }

    // a card that grows keeps the item still on its own; a page at full height scrolls instead
    function _hold(): void {
        if (!root.item || !isFinite(root._y)) return
        const view = root._viewport()
        if (!view || (view.scrollHold !== undefined && view.scrollHold !== root)) return
        const drift = root.item.mapToItem(null, 0, 0).y - root._y
        if (Math.abs(drift) < 0.5) return
        const top = Number(view.originY || 0)
        const bottom = top + Math.max(0, view.contentHeight - view.height)
        view.contentY = Math.max(top, Math.min(bottom, view.contentY + drift))
    }

    readonly property Connections _watch: Connections {
        target: root.watched
        enabled: isFinite(root._y)
        function onHeightChanged() { Qt.callLater(root._hold) }
    }
    readonly property Timer _release: Timer {
        interval: Motion.medium + 120
        onTriggered: root.release()
    }
}
