pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool   mediaProgress:       false
    property bool   workspaceShift:      true
    property bool   neutralTheme:        true
    property bool   neutralAccentAuto:   false
    property string neutralAccent:       "#bb9af7"   // soft violet; sits in a hue gap from the Tokyo Night status colors
    property string baseTone:            "charcoal"
    property bool   networkTrafficStats: false
    property bool   networkSpeedInline:  false   // pin the live up/down speed next to the icon, not just on hover
    property bool   netVpnShowLink:      false   // show "VPN / wifi|eth" so the underlying link stays visible
    property bool   showSeconds:         false
    property bool   compactDate:         false
    property bool   clock12h:            false
    property bool   showWindowTitle:     false
    property bool   showWindowTitleApp:  false
    property real   windowTitleOpacity:  1.0   // opacity of the whole title line (app + title)
    property bool   updatesWidget:       false
    property bool   trayWidget:          false
    property bool   valuesOnHover:       false
    property bool   batteryAutoHide:     false

    property bool   osdEnabled:     true
    property int    osdTimeout:     2000
    property string osdKindFilter:  "both"   // "both" | "volume" | "brightness"
    property bool   osdBatteryWarn: false
    property bool   osdTempWarn:    false
    property bool   osdShimmer:     false
    property bool   osdVolumeTint:  false    // warm "loud" tint as volume nears max
    property bool   osdChargedNotify: false  // one-shot OSD peek when the battery reaches full
    property bool   osdBarIntegrated: false  // β: show OSD inline in the bar center instead of a floating pill
    property bool   reduceMotion:        false
    property real   animSpeed:           1.0
    property real   uiScale:             1.0     // shell font scale, 0.8–1.15

    property bool   notifPopupEnabled:   true
    property bool   notifFullscreenSilence: false  // archive popups while a window is fullscreen
    property string notifPosition:       "top-right"  // "top-right" | "top-left" | "top-center"
    property int    notifMaxVisible:     5            // 0 = unlimited
    property string mediaWidgetFormat:   "title"  // "title" | "artist-title"
    property int    tempHotThreshold:    90
    property int    batteryLowThreshold: 20
    property int    notifDefaultTimeout: 5000
    property int    sysAlertTimeout:     10000  // auto-close (ms) for silere's battery/temp alert notifications; 0 = stay until clicked
    property bool   clockShowDate:       false
    property bool   barBorderVisible:    false
    property real   barLineStrength:     1.0

    property bool   underlineGlow:       false
    property bool   underlineIdleGlow:   false
    property bool   underlineNotifGlow:  false
    property bool   underlineBattGlow:   false
    property bool   underlineNetGlow:        false
    property bool   underlineTempGlow:       false
    property bool   underlineScreenshotGlow: false
    property real   glowStrength:            1.0
    property real   activeGlowStrength:      1.0
    property real   screenshotGlowStrength:  1.0
    property int    screenshotGlowDuration:  700
    property bool   screenshotGlowSweep:     true

    property real   dotOpacity:          0.35
    property string dotStyle:            "·"       // "·" | "•" | "◦" | "|" | "slash" | "line"
    property int    barSpacing:          11        // gap between bar widgets / separators
    property bool   barCompact:          false     // β: fewer separators, tighter gaps
    property int    barHeight:           36
    property bool   barFloating:         false     // detached rounded surface, matches the menu/calendar/notif panels
    property real   barWidth:            0.90     // visual bar width, 0.5-1.0 of screen
    property string barCornerStyle:      "round"  // "flat" | "round"
    property int    barRadius:           14       // rounded-corner radius in px
    property bool   barShadow:           false    // drop shadow under the floating surface
    property real   barShadowStrength:   1.0      // scales the floating shadow's depth, 0.3-2.0
    property string barPosition:         "top"     // "top" | "bottom"
    property real   barOpacity:          0.82
    property string barDisabledMonitors: ""        // comma-joined connector names whose bar is hidden
    property string overlayMonitor:      ""        // "" = follow focus; else a monitor connector name for notifs/OSD

    property int    nightLightTemp:      3500   // color temperature for hyprsunset, in Kelvin
    property real   nightLightLat:      45.0   // latitude for solar suggestion, degrees N (+) / S (-)
    property bool   nightLightAuto:     false  // auto-follow solar position

    property int    wsMinVisible:        5
    property bool   wsShowNumbers:       false
    property bool   wsRomanNumerals:     false
    property bool   wsScrollSwitch:      true
    property bool   wsShowAppIcons:      false
    property bool   wsNotifPulse:        false
    property real   wsIconOpacity:       0.85
    property int    wsIconSize:          16

    property bool _loaded: false
    property bool _configDirReady: false
    property bool _savePendingForDir: false
    // Placement-dependent windows wait for this before mapping, so a saved
    // non-default barPosition doesn't flash at the wrong edge first.
    readonly property bool ready: _loaded
    readonly property int _settingsVersion: 1
    property var _defaults: ({})
    property string _lastSavedJson: ""

    // Drives load/save/change-tracking. t: bool|int|real|enum|re;
    // int/real use min/max, enum uses vals, re uses a pattern.
    readonly property var _schema: [
        { k: "mediaProgress",       t: "bool" },
        { k: "workspaceShift",      t: "bool" },
        { k: "neutralTheme",        t: "bool" },
        { k: "neutralAccentAuto",   t: "bool" },
        { k: "neutralAccent",       t: "re",   re: /^#[0-9a-fA-F]{6}$/ },
        { k: "baseTone",            t: "enum", vals: ["charcoal", "black"] },
        { k: "networkTrafficStats", t: "bool" },
        { k: "networkSpeedInline",  t: "bool" },
        { k: "netVpnShowLink",      t: "bool" },
        { k: "showSeconds",         t: "bool" },
        { k: "compactDate",         t: "bool" },
        { k: "clock12h",            t: "bool" },
        { k: "showWindowTitle",     t: "bool" },
        { k: "showWindowTitleApp",  t: "bool" },
        { k: "windowTitleOpacity",  t: "real", min: 0.2, max: 1.0 },
        { k: "updatesWidget",       t: "bool" },
        { k: "trayWidget",          t: "bool" },
        { k: "valuesOnHover",       t: "bool" },
        { k: "batteryAutoHide",     t: "bool" },
        { k: "osdEnabled",          t: "bool" },
        { k: "osdTimeout",          t: "int",  min: 500,  max: 10000 },
        { k: "osdKindFilter",       t: "enum", vals: ["both", "volume", "brightness"] },
        { k: "osdBatteryWarn",      t: "bool" },
        { k: "osdTempWarn",         t: "bool" },
        { k: "osdShimmer",          t: "bool" },
        { k: "osdVolumeTint",       t: "bool" },
        { k: "osdChargedNotify",    t: "bool" },
        { k: "osdBarIntegrated",    t: "bool" },
        { k: "reduceMotion",        t: "bool" },
        { k: "animSpeed",           t: "real", min: 0.5, max: 2.0 },
        { k: "uiScale",             t: "real", min: 0.8, max: 1.15 },
        { k: "notifPopupEnabled",   t: "bool" },
        { k: "notifFullscreenSilence", t: "bool" },
        { k: "notifPosition",       t: "enum", vals: ["top-right", "top-left", "top-center"] },
        { k: "notifMaxVisible",     t: "int",  min: 0, max: 20 },
        { k: "mediaWidgetFormat",   t: "enum", vals: ["title", "artist-title"] },
        { k: "tempHotThreshold",    t: "int",  min: 50,   max: 105 },
        { k: "batteryLowThreshold", t: "int",  min: 5,    max: 50 },
        { k: "notifDefaultTimeout", t: "int",  min: 1000, max: 30000 },
        { k: "sysAlertTimeout",     t: "int",  min: 0,    max: 30000 },
        { k: "clockShowDate",       t: "bool" },
        { k: "barBorderVisible",    t: "bool" },
        { k: "barLineStrength",     t: "real", min: 0.5, max: 2.0 },
        { k: "underlineGlow",       t: "bool" },
        { k: "underlineIdleGlow",   t: "bool" },
        { k: "underlineNotifGlow",  t: "bool" },
        { k: "underlineBattGlow",   t: "bool" },
        { k: "underlineNetGlow",    t: "bool" },
        { k: "underlineTempGlow",   t: "bool" },
        { k: "underlineScreenshotGlow", t: "bool" },
        { k: "glowStrength",        t: "real", min: 0.5, max: 2.0 },
        { k: "activeGlowStrength",  t: "real", min: 0.1, max: 1.0 },
        { k: "screenshotGlowStrength", t: "real", min: 0.4, max: 1.8 },
        { k: "screenshotGlowDuration", t: "int",  min: 250, max: 1600 },
        { k: "screenshotGlowSweep", t: "bool" },
        { k: "dotOpacity",          t: "real", min: 0.05, max: 1.0 },
        { k: "dotStyle",            t: "enum", vals: ["·", "•", "◦", "|", "slash", "line"] },
        { k: "barSpacing",          t: "int",  min: 4, max: 24 },
        { k: "barCompact",          t: "bool" },
        { k: "barHeight",           t: "int",  min: 24,   max: 60 },
        { k: "barFloating",         t: "bool" },
        { k: "barWidth",            t: "real", min: 0.5,  max: 1.0 },
        { k: "barCornerStyle",      t: "enum", vals: ["flat", "round"] },
        { k: "barRadius",           t: "int",  min: 0,    max: 28 },
        { k: "barShadow",           t: "bool" },
        { k: "barShadowStrength",   t: "real", min: 0.3,  max: 2.0 },
        { k: "barPosition",         t: "enum", vals: ["top", "bottom"] },
        { k: "barOpacity",          t: "real", min: 0.4,  max: 1.0 },
        { k: "barDisabledMonitors", t: "re",   re: /^[A-Za-z0-9._,-]*$/ },
        { k: "overlayMonitor",      t: "re",   re: /^[A-Za-z0-9._-]*$/ },

        { k: "nightLightTemp",      t: "int",  min: 1000, max: 6500 },
        { k: "nightLightLat",      t: "real", min: -90.0, max: 90.0 },
        { k: "nightLightAuto",     t: "bool" },
        { k: "wsMinVisible",        t: "int",  min: 1,    max: 10 },
        { k: "wsShowNumbers",       t: "bool" },
        { k: "wsRomanNumerals",     t: "bool" },
        { k: "wsScrollSwitch",      t: "bool" },
        { k: "wsShowAppIcons",      t: "bool" },
        { k: "wsNotifPulse",        t: "bool" },
        { k: "wsIconOpacity",       t: "real", min: 0.3, max: 1.0 },
        { k: "wsIconSize",          t: "int",  min: 12,  max: 20 }
    ]

    function _coerce(s, v): void {
        switch (s.t) {
        case "bool": root[s.k] = !!v; break
        case "int":  { const n = parseInt(v);   if (!isNaN(n)) root[s.k] = Math.max(s.min, Math.min(s.max, n)); break }
        case "real": { const n = parseFloat(v); if (!isNaN(n)) root[s.k] = Math.max(s.min, Math.min(s.max, n)); break }
        case "enum": if (s.vals.indexOf(v) >= 0) root[s.k] = v; break
        case "re":   if (typeof v === "string" && s.re.test(v)) root[s.k] = v; break
        }
    }

    function _sameValue(a, b): bool {
        if (typeof a === "number" && typeof b === "number")
            return Math.abs(a - b) < 0.0001
        return a === b
    }

    function _captureDefaults(): var {
        const d = {}
        for (let i = 0; i < _schema.length; i++) d[_schema[i].k] = root[_schema[i].k]
        return d
    }

    function _migrate(j): var {
        // v0 wrote every key and had no version marker. Unknown/deprecated keys
        // are intentionally dropped on the next save by _save().
        delete j.midnightNeutral
        delete j.warmNeutral
        delete j.screenshotGlowTint
        return j
    }

    function _onSettingChanged(): void { if (_loaded) _writeTimer.restart() }

    function resetToDefaults(): void {
        for (let i = 0; i < _schema.length; i++)
            root[_schema[i].k] = _defaults[_schema[i].k]
    }

    Component.onDestruction: {
        _writeTimer.stop()
        if (!_configDirReady)
            console.warn("silere-shell: saving settings before config dir is ready:", _configDir)
        _save(true)   // blocking write, so the quit-time save actually lands
    }

    Component.onCompleted: {
        _defaults = _captureDefaults()
        // Restart the debounced save on any setting change, one connection per
        // property, derived from the schema, so a new setting can't be forgotten.
        for (let i = 0; i < _schema.length; i++)
            root[_schema[i].k + "Changed"].connect(root._onSettingChanged)
        root._ensureConfigDir()
    }

    readonly property string _configDir: {
        const env = Quickshell.env("XDG_CONFIG_HOME")
        const base = (env && String(env).length > 0)
            ? String(env)
            : String(Quickshell.env("HOME")) + "/.config"
        return base + "/silere-shell"
    }

    function _ensureConfigDir(): void {
        if (_configDirReady || _mkdirProc.running) return
        _mkdirProc.running = true
    }

    Process {
        id: _mkdirProc
        command: ["mkdir", "-p", root._configDir]
        onExited: (code) => {
            root._configDirReady = true
            if (code !== 0)
                console.warn("silere-shell: failed to create settings directory:", root._configDir)
            if (root._savePendingForDir) {
                root._savePendingForDir = false
                root._save()
            }
        }
    }

    // Native file IO (no bash spawns): atomic writes, and watchChanges means an
    // external edit to settings.json hot-applies into the running shell.
    FileView {
        id: _file
        path: root._configDir + "/settings.json"
        watchChanges: true
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onLoaded:      root._applyText(_file.text())
        onLoadFailed:  root._loaded = true   // first run: defaults
        onFileChanged: reload()
    }

    function _applyText(t: string): void {
        const raw = (t || "").trim()
        // our own atomic write echoes back through the watcher; skip it
        if (raw === _lastSavedJson) { _loaded = true; return }
        try {
            const j = _migrate(JSON.parse(raw || "{}"))
            for (let i = 0; i < _schema.length; i++) {
                const s = _schema[i]
                if (j[s.k] !== undefined) _coerce(s, j[s.k])
            }
        } catch(e) { console.warn("silere-shell: failed to parse settings.json, using defaults:", String(e)) }
        _loaded = true
    }

    Timer {
        id: _writeTimer
        interval: 400
        onTriggered: root._save()
    }

    function _save(force): void {
        if (!force && !_configDirReady) {
            _savePendingForDir = true
            _ensureConfigDir()
            return
        }
        const out = { __version: _settingsVersion }
        for (let i = 0; i < _schema.length; i++) {
            const key = _schema[i].k
            if (!root._sameValue(root[key], root._defaults[key]))
                out[key] = root[key]
        }
        const j = JSON.stringify(out)
        if (j === _lastSavedJson) return
        _lastSavedJson = j
        _file.setText(j + "\n")
    }
}
