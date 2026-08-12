import QtQuick
import "../../config"

ListView {
    id: root

    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    // one scroll feel shell-wide: drag stops at the edge, a flick still rebounds
    boundsMovement: Flickable.StopAtBounds

    // arrow stepping has to wait for the delegate: a row scrolled into view from outside
    // the cache buffer does not exist yet on the frame the key arrives
    function focusIndex(index: int): void {
        if (root.count <= 0) return
        const i = Math.max(0, Math.min(root.count - 1, index))
        root.currentIndex = i
        root.positionViewAtIndex(i, ListView.Contain)
        Qt.callLater(function() {
            const item = root.itemAtIndex(i)
            if (!item) return
            // a wrapper delegate owns the focusable row, not the item the view hands back
            if (item.focusRow) item.focusRow()
            else item.forceActiveFocus()
        })
    }
}
