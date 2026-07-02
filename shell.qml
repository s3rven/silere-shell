//@ pragma UseQApplication
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "modules/bar"
import "modules/osd"
import "modules/notifications"
import "modules/menu"
import "modules/calendar"
import "modules/traymenu"
import "modules/quickactions"
import "services"
import "config"

ShellRoot {
    id: root

    property bool pickerActive: false
    property bool pickerWatcherReady: false

    readonly property ShellScreen activeOverlayScreen: Monitors.overlayScreen

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    // Quickshell lazy-loads singletons, reading a member instantiates them; a
    // bare type reference would not. These are startup diagnostics/alerts whose
    // watchers must arm even before the user opens a related panel.
    Component.onCompleted: {
        void SystemAlerts.armed
        void NotifWatch.armed
        void Screenshot.armed
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: root.pickerWatcherReady = true
    }

    // Watch picker lock, state dir gets many unrelated writes, filter to just this file
    Process {
        id: pickerWatcher
        running: root.pickerWatcherReady && SystemTools.ready && SystemTools.hasInotifywait
        // The shell resolves XDG_STATE_HOME, then execs inotifywait so reloads
        // kill the watcher directly instead of orphaning a pipeline.
        command: ["bash", "-c",
            "state=\"${XDG_STATE_HOME:-$HOME/.local/state}\"; " +
            "mkdir -p \"$state\"; " +
            "lock=\"$state/wallpaper-picker.lock\"; " +
            "[ -f \"$lock\" ] && echo active || echo inactive; " +
            "exec inotifywait -m -q -e create,delete,moved_to,moved_from --format '%e|%f' \"$state\" 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                const s = line.trim()
                if (s === "active" || s === "inactive") {
                    root.pickerActive = (s === "active")
                    return
                }
                const parts = s.split("|")
                if (parts.length < 2 || parts[1] !== "wallpaper-picker.lock") return
                root.pickerActive = parts[0].indexOf("DELETE") < 0
                    && parts[0].indexOf("MOVED_FROM") < 0
            }
        }
        Component.onDestruction: running = false
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: _barScope
            required property ShellScreen modelData

            // Recreate the bar window when it changes edges: remapping a live
            // layer-shell surface's anchors leaves stale geometry on the old
            // edge, so the surface must be torn down and mapped fresh. First
            // map waits for settings so a saved bottom bar starts at the
            // bottom instead of flashing top-then-recreating.
            LazyLoader {
                id: _barLoader
                active: false
                readonly property bool barOn: ShellSettings.ready && Monitors.barEnabled(_barScope.modelData)
                readonly property string barPos: ShellSettings.barPosition
                onBarOnChanged: active = barOn
                Component.onCompleted: active = barOn
                onBarPosChanged: {
                    if (!active) return
                    active = false
                    Qt.callLater(() => _barLoader.active = _barLoader.barOn)
                }
                component: Bar { targetScreen: _barScope.modelData; pickerActive: root.pickerActive }
            }
        }
    }

    // Popup surfaces are relatively large object trees, even while their
    // PanelWindow is unmapped. Build them only when they have content to show.
    // Menu/calendar/tray loaders stay alive through their window's close
    // animation; OSD and notification models remove their final entry only
    // after the delegate exit animation has completed.
    LazyLoader {
        id: _osdLoader
        active: false
        Component.onCompleted: if (OsdBarState.activeCount > 0) active = true
        component: OsdWindow { targetScreen: root.activeOverlayScreen }
    }
    Connections {
        target: OsdBarState
        function onActiveCountChanged() {
            if (OsdBarState.activeCount > 0) {
                _osdUnload.stop()
                _osdLoader.active = true
            } else {
                _osdUnload.restart()
            }
        }
    }
    Timer { id: _osdUnload; interval: 50; onTriggered: _osdLoader.active = false }

    LazyLoader {
        id: _notificationLoader
        active: ShellSettings.notifPopupEnabled && Notifications.activeCount > 0
        component: NotificationPopups { targetScreen: root.activeOverlayScreen }
    }

    LazyLoader {
        id: _menuLoader
        active: false
        Component.onCompleted: if (MenuState.open) active = true
        component: MenuWindow { targetScreen: MenuState.triggerScreen ?? root.activeOverlayScreen }
    }
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open) {
                _menuUnload.stop()
                _menuLoader.active = true
            } else {
                _menuUnload.restart()
            }
        }
    }
    Timer { id: _menuUnload; interval: Math.max(80, Motion.ms(220) + 80); onTriggered: _menuLoader.active = false }

    LazyLoader {
        id: _calendarLoader
        active: false
        Component.onCompleted: if (CalendarState.open) active = true
        component: CalendarPopup { targetScreen: CalendarState.triggerScreen ?? root.activeOverlayScreen }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() {
            if (CalendarState.open) {
                _calendarUnload.stop()
                _calendarLoader.active = true
            } else {
                _calendarUnload.restart()
            }
        }
    }
    Timer { id: _calendarUnload; interval: Math.max(80, Motion.ms(210) + 80); onTriggered: _calendarLoader.active = false }

    LazyLoader {
        id: _trayMenuLoader
        active: false
        Component.onCompleted: if (TrayMenuState.open) active = true
        component: TrayMenuPopup { targetScreen: TrayMenuState.triggerScreen ?? root.activeOverlayScreen }
    }
    Connections {
        target: TrayMenuState
        function onOpenChanged() {
            if (TrayMenuState.open) {
                _trayMenuUnload.stop()
                _trayMenuLoader.active = true
            } else {
                _trayMenuUnload.restart()
            }
        }
    }
    Timer { id: _trayMenuUnload; interval: Math.max(80, Motion.ms(210) + 80); onTriggered: _trayMenuLoader.active = false }

    LazyLoader {
        id: _quickActionsLoader
        active: false
        Component.onCompleted: if (QuickActionsState.open) active = true
        component: QuickActionsPopup { targetScreen: QuickActionsState.triggerScreen ?? root.activeOverlayScreen }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() {
            if (QuickActionsState.open) {
                _quickActionsUnload.stop()
                _quickActionsLoader.active = true
            } else {
                _quickActionsUnload.restart()
            }
        }
    }
    Timer { id: _quickActionsUnload; interval: Math.max(80, Motion.ms(210) + 80); onTriggered: _quickActionsLoader.active = false }
}
