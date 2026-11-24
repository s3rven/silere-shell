import QtQuick

QtObject {
    readonly property Binding _wanted: Binding {
        target: DateTime
        property: "wanted"
        value: DateTime.clockNeeded(ShellSettings.barShowClock, OverviewState.active,
            ShellSettings.dndSchedule || Notifications.dndUntil > 0 || Idle.keepAwakeUntil > 0,
            MenuState.homeActive || (MenuState.settingsActive && MenuState.settingsSection === "clock"),
            CalendarState.open)
    }
    readonly property Binding _overview: Binding {
        target: DateTime
        property: "overviewOpen"
        value: OverviewState.active
    }
    // a surface opening after a suspend shows the time at once rather than at the next tick
    readonly property Connections _calendar: Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) DateTime.catchUp() }
    }
    readonly property Connections _menu: Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) DateTime.catchUp() }
    }
    // NetworkManager parks every device for sleep and brings them back within seconds of wake
    readonly property Connections _network: Connections {
        target: Network
        function onConnectedChanged() { DateTime.catchUp() }
    }
}
