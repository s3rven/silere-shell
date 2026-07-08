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

    // Quickshell lazy-loads singletons — reading a member instantiates them, a bare type reference won't.
    // these are startup diagnostics/alerts whose watchers must arm before the user opens a panel.
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
        // shell resolves XDG_STATE_HOME then execs inotifywait so reloads kill the watcher directly, not orphan a pipeline
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

            // recreate the bar window on edge change: remapping a live layer-shell surface's anchors leaves stale geometry, so tear down + map fresh.
            // first map waits for settings so a saved bottom bar starts at the bottom instead of flashing top-then-recreating.
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

    // popup surfaces are large object trees even while unmapped — build only when they have content, tear down unloadDelay after close so the exit anim finishes on a live surface.
    // notification popups skip the delay: their model drops the final entry only after the delegate exit anim completes.
    component PopupLoader: Scope {
        id: _pl
        required property bool wantOpen
        required property Component surface
        property int unloadDelay: Math.max(80, Motion.ms(210) + 80)
        onWantOpenChanged: {
            if (wantOpen) { _plUnload.stop(); _plLoader.active = true }
            else _plUnload.restart()
        }
        LazyLoader {
            id: _plLoader
            active: false
            // wantOpen can already be true on (re)load; the binding won't fire a change for the initial value
            Component.onCompleted: if (_pl.wantOpen) active = true
            component: _pl.surface
        }
        Timer { id: _plUnload; interval: _pl.unloadDelay; onTriggered: _plLoader.active = false }
    }

    PopupLoader {
        wantOpen: OsdBarState.activeCount > 0
        unloadDelay: 50
        surface: Component { OsdWindow { targetScreen: root.activeOverlayScreen } }
    }

    LazyLoader {
        active: ShellSettings.notifPopupEnabled && Notifications.activeCount > 0
        component: NotificationPopups { targetScreen: root.activeOverlayScreen }
    }

    PopupLoader {
        wantOpen: MenuState.open
        unloadDelay: Math.max(80, Motion.ms(220) + 80)
        surface: Component { MenuWindow { targetScreen: MenuState.triggerScreen ?? root.activeOverlayScreen } }
    }

    PopupLoader {
        wantOpen: CalendarState.open
        surface: Component { CalendarPopup { targetScreen: CalendarState.triggerScreen ?? root.activeOverlayScreen } }
    }

    PopupLoader {
        wantOpen: TrayMenuState.open
        surface: Component { TrayMenuPopup { targetScreen: TrayMenuState.triggerScreen ?? root.activeOverlayScreen } }
    }

    PopupLoader {
        wantOpen: QuickActionsState.open
        surface: Component { QuickActionsPopup { targetScreen: QuickActionsState.triggerScreen ?? root.activeOverlayScreen } }
    }
}
