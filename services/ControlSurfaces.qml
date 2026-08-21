pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // one list, so a row reused in another panel does not leave its service keyed to the first
    readonly property bool anyOpen: MenuState.open || QuickActionsState.open

    signal opened()

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root.opened() }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() { if (QuickActionsState.open) root.opened() }
    }
}
