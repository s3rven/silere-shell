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

    // reading a member instantiates a lazy singleton; these watchers must arm before the user opens a panel
    Component.onCompleted: {
        void NotifWatch.armed
        // PowerProfiles reads on menu-open: created lazily it misses the first open and the row sits on "Unavailable"
        void PowerProfiles.available
        // documented as always callable (`ipc call screenshot flash`), so it can't wait on the underline
        void Screenshot.armed
        // same trap: nothing else references ShellUpdate until the Updates page builds, after open
        void ShellUpdate.pending
        void OverlayCoordinator.armed
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

            // recreate the window on edge change: remapping a live layer-shell surface leaves stale geometry; the first map waits for settings
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

    component PopupLoader: Scope {
        id: _pl
        required property bool wantOpen
        required property Component surface
        property int unloadDelay: Math.max(40,
            Math.max(Motion.popOut, Motion.popOutFade) + 30)
        onWantOpenChanged: {
            if (wantOpen) { _plUnload.stop(); _plLoader.active = true }
            else _plUnload.restart()
        }
        LazyLoader {
            id: _plLoader
            active: false
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
