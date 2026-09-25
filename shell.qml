//@ pragma UseQApplication
// Regular Qt Quick animations fall back to a ~16 ms GUI timer while Silere's
// bar and a popup are both visible. The elapsed-time driver avoids that
// multi-window fallback; DefaultEnv still lets a user or driver override it.
//@ pragma DefaultEnv QSG_USE_SIMPLE_ANIMATION_DRIVER = 1
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

    readonly property bool smokeTest: Quickshell.env("SILERE_SMOKE_TEST") === "1"
    settings.watchFiles: !smokeTest && Quickshell.env("SILERE_WATCH_FILES") !== "0"
    readonly property ShellScreen activeOverlayScreen: smokeTest ? null : Monitors.overlayScreen
    // bar-anchored popups open with no trigger screen over IPC, and the overlay screen
    // is whichever one has focus — including one the user turned the bar off on
    readonly property ShellScreen anchoredPopupScreen: smokeTest ? null : Monitors.overlayBarScreen

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
        if (root.smokeTest) return
        void NotifWatch.armed
        // PowerProfiles reads when a panel opens: created lazily it misses the first open and the row sits on "Unavailable"
        void PowerProfiles.available
        // documented as always callable (`ipc call screenshot flash`), so it can't wait on the underline
        void Screenshot.armed
        // same trap: nothing else references ShellUpdate until the Updates page builds, after open
        void ShellUpdate.pending
        void OverlayCoordinator.armed
        void ControlSurfaces.anyOpen
        // the anchored popup states own the documented IPC targets and the shared control
        // rows, so they cannot wait on the panel that happens to host them
        void MenuState.armed
        void CalendarState.armed
        void TrayMenuState.armed
        void QuickActionsState.armed
        // auto night light tracks the sun, and one left on returns after a restart; otherwise lazy
        if (ShellSettings.nightLightAuto || ShellSettings.nightLightOn) void NightLight.toolAvailable
        // nothing else references Hooks: unarmed it never scans, and no hook ever fires
        void Hooks.armed
        root.armSystemAlertsIfNeeded()
    }

    Connections {
        target: ShellSettings
        function onOsdBatteryWarnChanged() { if (!root.smokeTest) root.armSystemAlertsIfNeeded() }
        function onOsdTempWarnChanged() { if (!root.smokeTest) root.armSystemAlertsIfNeeded() }
        function onNightLightAutoChanged() {
            if (!root.smokeTest && ShellSettings.nightLightAuto) void NightLight.toolAvailable
        }
        function onNightLightOnChanged() {
            if (!root.smokeTest && ShellSettings.nightLightOn) void NightLight.toolAvailable
        }
    }

    Variants {
        model: root.smokeTest ? [] : Quickshell.screens
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
        property bool warm: false
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
            if ((_plLoader.loading || _plLoader.active) && _pl._latchedScreen
                    && _pl.requestedScreen
                    && _pl._latchedScreen !== _pl.requestedScreen) {
                _plLoader.loading = false
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

        function _ensureWarm(): void {
            if (!_pl.warm || _pl.wantOpen) return
            _plUnload.stop()
            // An asynchronously prepared layer surface is still tied to its
            // output. A hover that moves between bars must restart for the new
            // screen instead of finishing a surface that cannot be remapped.
            if ((_plLoader.loading || _plLoader.active)
                    && _pl._latchedScreen
                    && _pl.requestedScreen
                    && _pl._latchedScreen !== _pl.requestedScreen) {
                _plLoader.loading = false
                _plLoader.active = false
            }
            if (!_plLoader.loading && !_plLoader.active) {
                _pl._latchedScreen = _pl.requestedScreen
                _plLoader.loading = true
            }
        }

        onWantOpenChanged: {
            if (wantOpen) _pl._ensureLoaded()
            else if (warm) _pl._ensureWarm()
            else _plUnload.restart()
        }
        onWarmChanged: {
            if (warm) _pl._ensureWarm()
            else {
                _plLoader.loading = false
                if (!wantOpen) _plUnload.restart()
            }
        }
        onRequestedScreenChanged: if (warm && !wantOpen) _pl._ensureWarm()
        LazyLoader {
            id: _plLoader
            active: false
            Component.onCompleted: {
                if (_pl.wantOpen) _pl._ensureLoaded()
                else if (_pl.warm) _pl._ensureWarm()
            }
            component: _pl.surface
        }
        Timer {
            id: _plUnload
            interval: _pl.unloadDelay
            onTriggered: {
                if (_pl.wantOpen || _pl.warm) return
                _plLoader.loading = false
                _plLoader.active = false
            }
        }
    }

    PopupLoader {
        id: _osdPopup
        wantOpen: !root.smokeTest && ShellSettings.osdEnabled && OsdBarState.activeCount > 0
            && (!ShellSettings.osdBarIntegrated || OsdBarState.barConcealed)
        requestedScreen: root.activeOverlayScreen
        unloadDelay: 50
        surface: Component { OsdWindow { targetScreen: _osdPopup.latchedScreen } }
    }

    PopupLoader {
        id: _notificationPopup
        wantOpen: !root.smokeTest && ShellSettings.notifPopupEnabled
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
        warm: !root.smokeTest && MenuState.warmRequested
        wantOpen: !root.smokeTest && MenuState.open
        requestedScreen: root.smokeTest ? null : MenuState.triggerScreen
            ?? MenuState.warmScreen
            ?? root.anchoredPopupScreen
        surface: Component { MenuWindow { targetScreen: _menuPopup.latchedScreen } }
    }

    PopupLoader {
        id: _calendarPopup
        wantOpen: !root.smokeTest && CalendarState.open
        requestedScreen: root.smokeTest ? null : CalendarState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { CalendarPopup { targetScreen: _calendarPopup.latchedScreen } }
    }

    PopupLoader {
        id: _trayPopup
        wantOpen: !root.smokeTest && TrayMenuState.open
        requestedScreen: root.smokeTest ? null : TrayMenuState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { TrayMenuPopup { targetScreen: _trayPopup.latchedScreen } }
    }

    PopupLoader {
        id: _quickActionsPopup
        wantOpen: !root.smokeTest && QuickActionsState.open
        requestedScreen: root.smokeTest ? null : QuickActionsState.triggerScreen ?? root.anchoredPopupScreen
        surface: Component { QuickActionsPopup { targetScreen: _quickActionsPopup.latchedScreen } }
    }
}
