pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true

    function _claim(name: string): void {
        if (name !== "menu") MenuState.close()
        if (name !== "calendar") CalendarState.close()
        if (name !== "tray") TrayMenuState.close()
        if (name !== "quickActions") QuickActionsState.close()
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._claim("menu") }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root._claim("calendar") }
    }
    Connections {
        target: TrayMenuState
        function onOpenChanged() { if (TrayMenuState.open) root._claim("tray") }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() { if (QuickActionsState.open) root._claim("quickActions") }
    }
}
