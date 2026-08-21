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
    // bar-anchored popups open with no trigger screen over IPC, and the overlay screen
    // is whichever one has focus — including one the user turned the bar off on
    readonly property ShellScreen anchoredPopupScreen: Monitors.overlayBarScreen

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
        // PowerProfiles reads when a panel opens: created lazily it misses the first open and the row sits on "Unavailable"
        void PowerProfiles.available
        // documented as always callable (`ipc call screenshot flash`), so it can't wait on the underline
        void Screenshot.armed
        // same trap: nothing else references ShellUpdate until the Updates page builds, after open
        void ShellUpdate.pending
        void OverlayCoordinator.armed
        void ControlSurfaces.anyOpen
        // nothing else references Hooks: unarmed it never scans, and no hook ever fires
        void Hooks.armed
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
        property ShellScreen requestedScreen: null
        readonly property ShellScreen latchedScreen: _latchedScreen
        property ShellScreen _latchedScreen: null
        property int unloadDelay: Math.max(40,
            Math.max(Motion.popOut, Motion.popOutFade) + 30)

        function _ensureLoaded(): void {
            _plUnload.stop()
            // A live layer-shell surface must stay on the screen it was
            // created for. A fast reopen on another output recreates it rather
            // than remapping the still-exiting surface in place.
            if (_plLoader.active && _pl._latchedScreen
                    && _pl.requestedScreen
                    && _pl._latchedScreen !== _pl.requestedScreen) {
                _plLoader.active = false
                _pl._latchedScreen = _pl.requestedScreen
                Qt.callLater(function() {
                    if (_pl.wantOpen) {
                        _pl._latchedScreen = _pl.requestedScreen
                        _plLoader.active = true
                    }
                })
                return
            }
            // Same-screen close/reopen can safely reverse the existing card.
            if (!_plLoader.active) _pl._latchedScreen = _pl.requestedScreen
            _plLoader.active = true
        }

        onWantOpenChanged: {
            if (wantOpen) _pl._ensureLoaded()
            else _plUnload.restart()
        }
        LazyLoader {
            id: _plLoader
            active: false
            Component.onCompleted: if (_pl.wantOpen) _pl._ensureLoaded()
            component: _pl.surface
        }
        Timer {
            id: _plUnload
            interval: _pl.unloadDelay
            onTriggered: {
                if (_pl.wantOpen) return
                _plLoader.active = false
            }
        }
    }

    PopupLoader {
        id: _osdPopup
        wantOpen: ShellSettings.osdEnabled && OsdBarState.activeCount > 0
        requestedScreen: root.activeOverlayScreen
        unloadDelay: 50
        surface: Component { OsdWindow { targetScreen: _osdPopup.latchedScreen } }
    }

    PopupLoader {
        id: _notificationPopup
        wantOpen: ShellSettings.notifPopupEnabled
            && Notifications.activeCount > 0
        requestedScreen: root.activeOverlayScreen
        surface: Component {
            NotificationPopups {
                targetScreen: _notificationPopup.latchedScreen
            }
        }
    }

    PopupLoader {
        id: _menuPopup
        wantOpen: MenuState.open
        requestedScreen: MenuState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { MenuWindow { targetScreen: _menuPopup.latchedScreen } }
    }

    PopupLoader {
        id: _calendarPopup
        wantOpen: CalendarState.open
        requestedScreen: CalendarState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { CalendarPopup { targetScreen: _calendarPopup.latchedScreen } }
    }

    PopupLoader {
        id: _trayPopup
        wantOpen: TrayMenuState.open
        requestedScreen: TrayMenuState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { TrayMenuPopup { targetScreen: _trayPopup.latchedScreen } }
    }

    PopupLoader {
        id: _quickActionsPopup
        wantOpen: QuickActionsState.open
        requestedScreen: QuickActionsState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { QuickActionsPopup { targetScreen: _quickActionsPopup.latchedScreen } }
    }
}
