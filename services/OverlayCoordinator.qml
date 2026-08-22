pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true

    function _environmentBlocksControls(idle: bool, overview: bool): bool {
        return idle || overview
    }

    function closeAll(): void {
        MenuState.close()
        CalendarState.close()
        TrayMenuState.close()
        QuickActionsState.close()
    }

    function _opened(name: string): void {
        // IPC and keybind requests can arrive after the environment edge that closed the surfaces, so reject re-entry until it becomes interactive
        if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active)) {
            root.closeAll()
            return
        }
        root._claim(name)
    }

    function _claim(name: string): void {
        if (name !== "menu") MenuState.close()
        if (name !== "calendar") CalendarState.close()
        if (name !== "tray") TrayMenuState.close()
        if (name !== "quickActions") QuickActionsState.close()
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._opened("menu") }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root._opened("calendar") }
    }
    Connections {
        target: TrayMenuState
        function onOpenChanged() { if (TrayMenuState.open) root._opened("tray") }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() { if (QuickActionsState.open) root._opened("quickActions") }
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
