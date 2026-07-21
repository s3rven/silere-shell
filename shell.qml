//@ pragma UseQApplication
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
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

    readonly property ShellScreen activeOverlayScreen: Monitors.overlayScreen

    function armSystemAlertsIfNeeded(): void {
        if (ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn)
            void SystemAlerts.armed
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    // Quickshell lazy-loads singletons — reading a member instantiates them, a bare type reference won't.
    // these are startup diagnostics/alerts whose watchers must arm before the user opens a panel.
    Component.onCompleted: {
        void NotifWatch.armed
        root.armSystemAlertsIfNeeded()
    }

    Connections {
        target: ShellSettings
        function onOsdBatteryWarnChanged() { root.armSystemAlertsIfNeeded() }
        function onOsdTempWarnChanged() { root.armSystemAlertsIfNeeded() }
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
                component: Bar { targetScreen: _barScope.modelData }
            }
        }
    }

    // popup surfaces are large object trees even while unmapped — build only when they have content, tear down unloadDelay after close so the exit anim finishes on a live surface.
    // notification popups skip the delay: their model drops the final entry only after the delegate exit anim completes.
    component PopupLoader: Scope {
        id: _pl
        required property bool wantOpen
        required property Component surface
        // Keep the tree only through the longest card exit, then release it.
        // The old ~290ms grace retained every popup for about twice as long as
        // its visible close transition.
        property int unloadDelay: Math.max(40,
            Math.max(Motion.popOut, Motion.popOutFade) + 30)
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
        wantOpen: ShellSettings.osdEnabled && OsdBarState.activeCount > 0
        unloadDelay: 50
        surface: Component { OsdWindow { targetScreen: root.activeOverlayScreen } }
    }

    LazyLoader {
        active: ShellSettings.notifPopupEnabled && Notifications.activeCount > 0
        component: NotificationPopups { targetScreen: root.activeOverlayScreen }
    }

    PopupLoader {
        wantOpen: MenuState.open
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
