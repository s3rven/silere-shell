import QtQuick
import "../../config"

// attach to the real control so pointer, keyboard, and assistive actions share one owner
Item {
    id: root

    property Item control: parent
    property bool interactive: true
    property bool adjustable: false
    property bool listNavigation: false
    property bool customNavigation: false
    // while a list is taking typed text, Space is part of it rather than a press
    property bool spaceIsText: false
    property bool ringShown: true
    property int _navigationToken: 0
    property real radius: Theme.radiusControl
    property real ringY: 0
    property real ringHeight: height
    signal activated()
    signal stepped(int direction, int multiplier)
    signal bounded(bool maximum)
    signal navigated(int direction)

    anchors.fill: parent
    z: 100
    readonly property bool canInteract: root.interactive && root.control
        && root.control.enabled && root.control.visible

    Binding { target: root.control; property: "activeFocusOnTab"; value: root.canInteract; delayed: true }
    onCanInteractChanged: {
        // clear focus before removing the tab stop, which Qt refuses while it owns focus
        if (!root.canInteract && root.control && root.control.activeFocus) root.control.focus = false
    }
    function handleKey(event): void {
        if (!root.canInteract || !root.control.activeFocus
                || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
        const key = event.key
        if (root.adjustable && [Qt.Key_Left, Qt.Key_Down, Qt.Key_Right, Qt.Key_Up,
                Qt.Key_PageDown, Qt.Key_PageUp, Qt.Key_Home, Qt.Key_End].indexOf(key) >= 0) {
            event.accepted = true
            if (key === Qt.Key_Home || key === Qt.Key_End) root.bounded(key === Qt.Key_End)
            else root.stepped(key === Qt.Key_Left || key === Qt.Key_Down || key === Qt.Key_PageDown ? -1 : 1,
                key === Qt.Key_PageDown || key === Qt.Key_PageUp || (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter
                || (key === Qt.Key_Space && !root.spaceIsText)) {
            event.accepted = true
            if (!event.isAutoRepeat) root.activated()
        } else if (root.listNavigation && (key === Qt.Key_Down || key === Qt.Key_Up)) {
            event.accepted = true
            if (root.customNavigation) root.navigated(key === Qt.Key_Down ? 1 : -1)
            else root.moveFocus(key === Qt.Key_Down ? 1 : -1)
        }
    }
    function moveFocus(direction: int): void {
        for (let item = root.control; item; item = item.parent) {
            const view = item.ListView.view
            if (!view || item.index === undefined) continue
            const start = item.index
            const origin = root.control
            const window = origin.Window.window
            const token = ++root._navigationToken
            const reason = direction > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason
            function wanted() {
                if (!view || !view.visible || !view.enabled || !root || token !== root._navigationToken) return false
                const focused = window ? window.activeFocusItem : null
                // pooled delegates can lose focus during a long search; another real tab stop takes ownership
                return !focused || focused === origin || !focused.activeFocusOnTab
            }
            function find(node) {
                if (!node || !node.visible || !node.enabled) return null
                if (node.activeFocusOnTab) return node
                for (let i = 0; i < node.children.length; i++) {
                    const found = find(node.children[i])
                    if (found) return found
                }
                return null
            }
            function visit(index) {
                if (!wanted()) return
                const exhausted = index < 0 || index >= view.count
                const target = exhausted ? Math.min(start, view.count - 1) : index
                view.currentIndex = target
                if (target < 0) return
                view.positionViewAtIndex(target, ListView.Contain)
                view.forceLayout()
                // newly created delegates need a turn to install their tab bindings
                Qt.callLater(function() {
                    if (!wanted()) return
                    const next = find(view.currentItem)
                    if (next) next.forceActiveFocus(reason)
                    else if (!exhausted) visit(index + direction)
                })
            }
            visit(start + direction)
            return
        }
        const next = root.control.nextItemInFocusChain(direction > 0)
        if (next) next.forceActiveFocus(Qt.TabFocusReason)
    }

    FocusScroll {
        id: _focusScroll
        control: root.control
        revealY: root.ringY
        revealHeight: root.ringHeight
        enabled: root.canInteract
    }
    Connections {
        target: root.control ? root.control.Keys : null
        function onPressed(event) { root.handleKey(event) }
    }
    function reveal(): void {
        _focusScroll.reveal()
    }

    Item {
        y: root.ringY
        width: parent.width
        height: root.ringHeight
        visible: root.ringShown && root.canInteract && root.control.activeFocus
        OutlineBorder {
            radius: root.radius
            outlineWidth: 2
            outlineColor: Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
        }
    }
}
