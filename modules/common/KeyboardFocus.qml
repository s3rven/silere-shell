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
    // a small button in a hit area as tall as its row, as a row's chevron, rings a circle this wide at its centre the
    // way an icon button does; around the whole area the ring ran the row's height and touched its edges
    property real ringSize: 0
    signal activated()
    signal stepped(int direction, int multiplier)
    signal bounded(bool maximum)
    signal navigated(int direction)

    anchors.fill: parent
    z: 100
    readonly property bool canInteract: root.interactive && root.control
        && root.control.enabled && root.control.visible

    Binding { target: root.control; property: "activeFocusOnTab"; value: root.canInteract; delayed: true }
    property Item _holder: null
    // the control held the keyboard focus itself. A ListView marks its current row focused for whenever the view
    // takes the focus, with no key ever pressed: read as owned, that row closing with its list pulled the focus onto
    // the list, and the next close handed it to the row's chevron, which drew its ring under the mouse. A property,
    // not a Connections: this sits on every control
    property bool _owned: false
    readonly property bool _focused: root.control ? root.control.activeFocus : false
    // moved on by hand, the focus is no longer this control's; hidden or disabled under it, it is until it parks
    on_FocusedChanged: {
        if (root._focused) root._owned = true
        else if (root.control && root.control.visible && root.control.enabled) root._owned = false
    }
    onCanInteractChanged: {
        const control = root.control
        if (!control) return
        if (root.canInteract) {
            if (root._holder && root._holder.activeFocus) control.forceActiveFocus(Qt.OtherFocusReason)
            root._holder = null
            root._owned = control.activeFocus
            return
        }
        if (!control.activeFocus && !root._owned) return
        root._owned = false
        const window = control.Window.window
        // the window root runs no key handler: park on the nearest shown ancestor, whether busy, hidden or disabled
        if (!window || (!control.activeFocus && window.activeFocusItem !== window.contentItem)) return
        for (let p = control.parent; p && p !== window.contentItem; p = p.parent) {
            if (!p.visible || !p.enabled) continue
            root._holder = p
            p.forceActiveFocus(Qt.OtherFocusReason)
            return
        }
        // clear focus before removing the tab stop, which Qt refuses while it owns focus
        if (control.activeFocus) control.focus = false
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

    // a disclosure returns focus only if it still owns it, before disabling its contents
    function restoreFrom(container: Item): bool {
        if (!root.canInteract || !container) return false
        const window = root.control.Window.window
        for (let item = window ? window.activeFocusItem : null; item; item = item.parent) {
            if (item !== container) continue
            root.control.forceActiveFocus(Qt.BacktabFocusReason)
            return true
        }
        return false
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
    function reveal(onlyAtRest = false): void {
        _focusScroll.reveal(onlyAtRest)
    }

    // built only for the control holding the focus: a Shape on every control of a panel was a
    // third of what this costs each one as the panel opens
    Loader {
        x: root.ringSize > 0 ? Math.round((root.width - root.ringSize) / 2) : 0
        y: root.ringSize > 0 ? Math.round((root.height - root.ringSize) / 2) : root.ringY
        width: root.ringSize > 0 ? root.ringSize : parent.width
        height: root.ringSize > 0 ? root.ringSize : root.ringHeight
        active: root.ringShown && root.canInteract && root.control.activeFocus
        sourceComponent: OutlineBorder {
            radius: root.ringSize > 0 ? root.ringSize / 2 : root.radius
            outlineWidth: 2
            outlineColor: Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
        }
    }
}
