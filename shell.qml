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
import "modules/common"
import "services"
import "config"

ShellRoot {
    id: root

    readonly property bool smokeTest: Quickshell.env("SILERE_SMOKE_TEST") === "1"
    // check.sh's smoke shells share the live display; a mapped bar would reserve its exclusive zone on the user's screen
    readonly property bool unmappedBars: Quickshell.env("SILERE_UNMAPPED_BARS") === "1"
    settings.watchFiles: !smokeTest && Quickshell.env("SILERE_WATCH_FILES") !== "0"
    readonly property ShellScreen activeOverlayScreen: smokeTest ? null : Monitors.overlayScreen
    // bar-anchored popups open with no trigger screen over IPC, and the overlay screen
    // is whichever one has focus — including one the user turned the bar off on
    readonly property ShellScreen anchoredPopupScreen: smokeTest ? null : Monitors.overlayBarScreen
    // only one popup is open at a time; the others' screens get a catcher for the closing click
    readonly property ShellScreen openPopupScreen: MenuState.open ? _menuPopup.latchedScreen
        : CalendarState.open ? _calendarPopup.latchedScreen
        : TrayMenuState.open ? _trayPopup.latchedScreen
        : QuickActionsState.open ? _quickActionsPopup.latchedScreen
        : null

    // auto night light tracks the sun, and one left on returns after a restart; otherwise lazy
    function armNightLightIfNeeded(): void {
        if (ShellSettings.nightLightAuto || ShellSettings.nightLightOn)
            void NightLight.armed
    }

    function armSystemAlertsIfNeeded(): void {
        if (ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn)
            void SystemAlerts.armed
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    // reading a member instantiates a lazy singleton; every service declaring `armed` is read here or in an arm function above
    Component.onCompleted: {
        if (root.smokeTest) return
        void NotifWatch.armed
        // the profile arrives over D-Bus ~300ms after the first read; armed on first open, the row shows the default
        void PowerProfiles.armed
        // documented as always callable (`ipc call screenshot flash`), so it can't wait on the underline
        void Screenshot.armed
        // same trap: nothing else references ShellUpdate until the Updates page builds, after open
        void ShellUpdate.armed
        void OverlayCoordinator.armed
        void ControlSurfaces.armed
        // the anchored popup states own the documented IPC targets and the shared control rows, so they cannot wait on the panel that happens to host them
        void MenuState.armed
        void CalendarState.armed
        void TrayMenuState.armed
        void QuickActionsState.armed
        // nothing else references Hooks: unarmed it never scans, and no hook ever fires
        void Hooks.armed
        root.armNightLightIfNeeded()
        root.armSystemAlertsIfNeeded()
    }

    Connections {
        target: ShellSettings
        enabled: !root.smokeTest
        function onOsdBatteryWarnChanged() { root.armSystemAlertsIfNeeded() }
        function onOsdTempWarnChanged() { root.armSystemAlertsIfNeeded() }
        function onNightLightAutoChanged() { root.armNightLightIfNeeded() }
        function onNightLightOnChanged() { root.armNightLightIfNeeded() }
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
                component: Bar { targetScreen: _barScope.modelData; visible: !root.unmappedBars }
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
        // The compositor closes a layer surface for good when its output goes
        // away, and the latched screen reads null from then on. A popup that is
        // still wanted, like a persistent notification, reopens on the screen
        // that took over instead of staying unmapped until it is dismissed.
        function _recoverLostScreen(): void {
            if (_pl._latchedScreen || !_pl.requestedScreen) return
            if (_plLoader.active) {
                _plUnload.stop()
                _plLoader.active = false
                Qt.callLater(function() {
                    if (_pl.wantOpen) _pl._ensureLoaded()
                    else if (_pl.warm) _pl._ensureWarm()
                })
            } else if (_plLoader.loading) {
                _plLoader.loading = false
                _pl._ensureWarm()
            }
        }
        on_LatchedScreenChanged: _pl._recoverLostScreen()
        onRequestedScreenChanged: {
            _pl._recoverLostScreen()
            if (warm && !wantOpen) _pl._ensureWarm()
        }
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
            && Notifications.activeCount > 0 && !OverlayCoordinator.notificationsHeld
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

    // any one screen holds the inhibitor; when that output goes away the surface is rebuilt on the next
    Variants {
        id: _keepAwakeSurfaces
        model: Idle.keepAwake && !root.smokeTest && Quickshell.screens.length > 0
            ? [Quickshell.screens[0]] : []
        delegate: KeepAwakeSurface {
            required property ShellScreen modelData
            targetScreen: modelData
        }
    }

    // a click on another monitor closes the popup; a compositor with a popup grab already hands it to the popup
    Variants {
        model: root.smokeTest || Compositor.popupGrab !== null ? [] : Quickshell.screens
        delegate: Scope {
            id: _dismissScope
            required property ShellScreen modelData

            LazyLoader {
                active: root.openPopupScreen !== null && _dismissScope.modelData !== root.openPopupScreen
                component: ScreenDismiss { targetScreen: _dismissScope.modelData }
            }
        }
    }
}
