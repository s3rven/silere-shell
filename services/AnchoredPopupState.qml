import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property ShellScreen triggerScreen: null

    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }

    // a destroyed widget nulls this with no assignment behind it. Reordering bar widgets
    // hands the zone's Repeater a new array, which rebuilds every delegate, so the anchor
    // drops for a turn and comes straight back; only a bar that really went never returns.
    property bool _anchorWriting: false
    function _setAnchor(source): void {
        _anchorRegrab.stop()
        root._anchorWriting = true
        root.anchorSource = source ?? null
        root._anchorWriting = false
    }
    // claimed by whichever live widget asks first, not by the one being rebuilt: a zone's
    // Repeater creates the replacements before it destroys the originals, and the
    // destruction is deferred, so an edge-triggered handover lands on a dying instance
    function adoptAnchor(source): void {
        if (!root.open || !source) return
        if (root._anchorWriting || root.anchorSource !== null) return
        root._setAnchor(source)
    }
    onAnchorSourceChanged: {
        if (anchorSource !== null) { _anchorRegrab.stop(); return }
        if (root._anchorWriting || !root.open) return
        _anchorRegrab.restart()
    }
    // never expose this timer's state: a consumer that reacts by taking the anchor stops
    // the very timer it is bound to, which is a binding loop
    Timer {
        id: _anchorRegrab
        interval: 150
        onTriggered: if (root.open && root.anchorSource === null) root.close()
    }

    function openAt(x: real, screen, source): void {
        root.anchorX = x
        root._setAnchor(source)
        root.triggerScreen = screen ?? null
        root.open = true
    }
    function close(): void {
        // open first: clearing anchorSource while open re-enters close() through its handler
        if (root.open) root.open = false
        root.triggerScreen = null
        root._setAnchor(null)
    }
}
