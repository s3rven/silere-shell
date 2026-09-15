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
            if (list[i] !== opener) list[i].close()
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
