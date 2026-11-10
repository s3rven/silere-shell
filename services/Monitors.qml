pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool _syncingPreferences: false

    function identity(screen): string {
        if (!screen) return ""
        const model = String(screen.model || "").trim()
        const serial = String(screen.serialNumber || "").trim()
        if (!model || !serial || model.length > 128 || serial.length > 128
                || /^(0+|0x0+|unknown|none|n\/a)$/i.test(serial)) return ""
        return encodeURIComponent(JSON.stringify([model, serial]))
    }

    function uniqueIdentity(screen, screens): string {
        const key = root.identity(screen)
        return key && screens.filter(s => root.identity(s) === key).length === 1 ? key : ""
    }

    function screenForPreference(name: string, key: string, screens): var {
        if (!name) return null
        if (key) {
            const matches = screens.filter(s => root.identity(s) === key)
            if (matches.length === 1) return matches[0]
        }
        const named = screens.find(s => s && s.name === name)
        // a different known display can occupy the old port; leave it on its own defaults
        return named && (!key || !root.identity(named) || root.identity(named) === key) ? named : null
    }

    function identityMap(raw: string): var {
        const result = Object.create(null)
        try {
            const parsed = JSON.parse(raw || "{}")
            if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") return result
            for (const name of Object.keys(parsed))
                if (/^[A-Za-z0-9._-]+$/.test(name) && typeof parsed[name] === "string"
                        && /^[A-Za-z0-9%._~!*'()-]{1,4096}$/.test(parsed[name])) result[name] = parsed[name]
        } catch (error) {}
        return result
    }

    // a changed name is the user's word (Settings, a hand edit or the CLI), so the identity is re-read from
    // that screen; a screen change keeps the identity, so the preference follows the display across ports
    property bool _rebindOverlayIdentity: false
    function rememberOverlay(): void {
        // the first load's change is the saved pair arriving, not a new choice: rebinding there dropped the identity of a display that was unplugged at startup
        if (root._syncingPreferences || !ShellSettings.ready) return
        root._rebindOverlayIdentity = true
    }
    // picking the same connector again is how a display that took over another's port takes over its pin
    function selectOverlay(name: string): void {
        root._rebindOverlayIdentity = true
        if (name === ShellSettings.overlayMonitor) Qt.callLater(root._syncPreferences)
        else ShellSettings.setValue("overlayMonitor", name)
    }
    function overlayIdentityFor(name: string, stored: string, rebind: bool, screens): string {
        if (!name) return ""
        if (rebind) {
            const chosen = screens.find(s => s && s.name === name)
            return chosen ? root.uniqueIdentity(chosen, screens) : ""
        }
        if (stored) return stored
        const pin = root.screenForPreference(name, "", screens)
        return pin ? root.uniqueIdentity(pin, screens) : ""
    }

    function _syncPreferences(): void {
        if (!ShellSettings.ready || ShellSettings._applying || root._syncingPreferences) return
        const screens = Quickshell.screens || []
        const name = ShellSettings.overlayMonitor
        const nextIdentity = root.overlayIdentityFor(name, ShellSettings.overlayMonitorIdentity,
            root._rebindOverlayIdentity, screens)
        root._rebindOverlayIdentity = false
        const pin = root.screenForPreference(name, nextIdentity, screens)
        const ids = root.identityMap(ShellSettings.barMonitorIdentities)
        const off = (ShellSettings.barDisabledMonitors || "").split(",").filter(s => s.length > 0)
        for (const name of off) {
            if (ids[name]) continue
            const screen = screens.find(s => s.name === name)
            const key = root.uniqueIdentity(screen, screens)
            if (key) ids[name] = key
        }
        for (const name of Object.keys(ids)) if (off.indexOf(name) < 0) delete ids[name]
        const nextIds = Object.keys(ids).length > 0 ? JSON.stringify(ids) : ""
        const nextName = name && pin ? pin.name : name
        if (nextName === ShellSettings.overlayMonitor && nextIdentity === ShellSettings.overlayMonitorIdentity
                && nextIds === ShellSettings.barMonitorIdentities) return
        root._syncingPreferences = true
        try {
            ShellSettings.batch(() => {
                ShellSettings.overlayMonitor = nextName
                ShellSettings.overlayMonitorIdentity = nextIdentity
                ShellSettings.barMonitorIdentities = nextIds
            }, false)
        } finally { root._syncingPreferences = false }
    }

    Component.onCompleted: Qt.callLater(root._syncPreferences)
    Connections {
        target: Quickshell
        function onScreensChanged() { Qt.callLater(root._syncPreferences) }
    }
    Connections {
        target: ShellSettings
        function onReadyChanged() { Qt.callLater(root._syncPreferences) }
        function onOverlayMonitorChanged() { root.rememberOverlay(); Qt.callLater(root._syncPreferences) }
        function onBarDisabledMonitorsChanged() { Qt.callLater(root._syncPreferences) }
    }

    readonly property ShellScreen overlayScreen: {
        const screens = Quickshell.screens
        if (!screens || screens.length === 0) return null

        const pin = root.screenForPreference(ShellSettings.overlayMonitor, ShellSettings.overlayMonitorIdentity, screens)
        if (pin) return pin

        const focused = Compositor.focusedMonitor
        if (focused && focused.length > 0) {
            for (let i = 0; i < screens.length; i++)
                if (screens[i].name === focused) return screens[i]
        }
        return screens[0]
    }

    readonly property string activeName: overlayScreen ? overlayScreen.name : ""

    // bar content only, so this resolves against the bar-hosting screen: the overlay screen
    // can be one with no bar, and that must not freeze the sole bar the user is looking at
    function isActive(screen): bool {
        return !screen || overlayBarName === screen.name
    }

    function _configuredBarEnabled(screen): bool {
        if (!screen) return false
        const off = ShellSettings.barDisabledMonitors
        if (!off || off.length === 0) return true
        const screens = Quickshell.screens || []
        const ids = root.identityMap(ShellSettings.barMonitorIdentities)
        return !off.split(",").some(name => root.screenForPreference(name, ids[name] || "", screens) === screen)
    }

    function barEnabled(screen): bool {
        if (!screen) return false
        if (_configuredBarEnabled(screen)) return true

        const screens = Quickshell.screens || []
        for (let i = 0; i < screens.length; i++)
            if (_configuredBarEnabled(screens[i])) return false

        // never focus-following: a moving fallback would rebuild the bar on every focus change
        const fallback = root.screenForPreference(ShellSettings.overlayMonitor, ShellSettings.overlayMonitorIdentity, screens)
            || screens[0]
        return !!fallback && fallback.name === screen.name
    }

    readonly property int liveBarCount: {
        const screens = Quickshell.screens || []
        let n = 0
        for (let i = 0; i < screens.length; i++) if (barEnabled(screens[i])) n++
        return n
    }

    readonly property ShellScreen overlayBarScreen: {
        const preferred = overlayScreen
        if (barEnabled(preferred)) return preferred

        const screens = Quickshell.screens || []
        for (let i = 0; i < screens.length; i++)
            if (barEnabled(screens[i])) return screens[i]
        return null
    }
    readonly property string overlayBarName: overlayBarScreen ? overlayBarScreen.name : ""

    function setBarEnabled(name: string, on: bool): void {
        if (!name || name.length === 0) return
        const screens = Quickshell.screens || []
        const screen = screens.find(s => s.name === name)
        if (!screen || (!on && root.barEnabled(screen) && root.liveBarCount <= 1)) return
        const ids = root.identityMap(ShellSettings.barMonitorIdentities)
        const parts = (ShellSettings.barDisabledMonitors || "").split(",").filter(s => s.length > 0
            && s !== name && root.screenForPreference(s, ids[s] || "", screens) !== screen)
        if (!on) {
            parts.push(name)
            const key = root.uniqueIdentity(screen, screens)
            if (key) ids[name] = key
            else delete ids[name]
        }
        for (const old of Object.keys(ids)) if (parts.indexOf(old) < 0) delete ids[old]
        root._syncingPreferences = true
        try {
            ShellSettings.batch(() => {
                ShellSettings.barDisabledMonitors = parts.join(",")
                ShellSettings.barMonitorIdentities = Object.keys(ids).length > 0 ? JSON.stringify(ids) : ""
            })
        } finally { root._syncingPreferences = false }
    }
}
