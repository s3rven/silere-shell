pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true
    readonly property var popups: root._popups
    property var _popups: []
    property int _openCount: 0
    readonly property bool anyOpen: root._openCount > 0

    function _environmentBlocksControls(idle: bool, overview: bool): bool {
        return idle || overview
    }

    // a card arriving over an open popup lands on top of it, so new ones wait for it to close; cards already showing stay, and a critical one releases them
    // set on edges only: bound to the popup's own load, it re-entered while the loader opened
    property bool notificationsHeld: false
    onAnyOpenChanged: if (!root._swapping) root.notificationsHeld = root.anyOpen && Notifications.activeCount === 0
    // a popup closing and reopening in one call (the tray stepping to the next app) keeps the hold it had
    property bool _swapping: false
    function swap(step): void {
        root._swapping = root.anyOpen
        try { step() } finally { root._swapping = false }
        if (!root.anyOpen) root.notificationsHeld = false
    }

    function registerPopup(state): void {
        if (!state || root._popups.indexOf(state) >= 0) return
        root._popups = root._popups.concat([state])
    }

    function popupOpened(state): void {
        root._openCount++
        // IPC and keybind requests can arrive after the environment edge that closed the surfaces, so reject re-entry until it becomes interactive
        if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active)) {
            root.closeAll()
            return
        }
        root._closeOthers(state)
    }

    function popupClosed(): void {
        root._openCount = Math.max(0, root._openCount - 1)
    }

    function closeAll(): void {
        // close() re-enters popupClosed, so iterate a copy that cannot shift underneath
        const list = root._popups.slice()
        for (let i = 0; i < list.length; i++) list[i].close()
    }

    function _closeOthers(opener): void {
        const list = root._popups.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i] === opener) continue
            if (list[i].open) root._handOver()
            list[i].close()
        }
    }

    // true for a moment after an open popup gave way to another (a keybind for the calendar over the menu). The one
    // leaving drops its surface from under the pointer, and Hyprland reads that as a click outside the new one's focus
    // grab, so the new one closed as it opened. Set on the edge, read only when a grab clears, so nothing binds a timer
    property bool handingOver: false
    function _handOver(): void {
        root.handingOver = true
        _handoverEnd.restart()
    }
    // past the leaving card's fade, when its surface unmaps
    Timer {
        id: _handoverEnd
        interval: 600
        onTriggered: root.handingOver = false
    }

    Connections {
        target: Notifications
        function onActiveCountChanged() {
            if (Notifications.activeCount === 0) root.notificationsHeld = root.anyOpen
        }
        function onLastCriticalChanged() {
            if (Notifications.lastCritical) root.notificationsHeld = false
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active))
                root.closeAll()
        }
    }
    Connections {
        target: OverviewState
        function onActiveChanged() {
            if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active))
                root.closeAll()
        }
    }
}
