pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool   mediaProgress:       false
    property bool   mediaWidgetHelper:   false
    property string mediaVisualizerPreset: "balanced"
    property string mediaVisualizerStyle:  "wave"
    property string mediaVisualizerPosition: "media"
    property bool   workspaceShift:      false
    property bool   neutralTheme:        true
    property bool   neutralAccentAuto:   false
    property string neutralAccent:       "#b8bdd8"
    property string matugenAccentRole:   "primary"
    property string baseTone:            "charcoal"
    property bool   networkTrafficStats: false
    property bool   networkSpeedInline:  false
    property bool   netVpnShowLink:      false
    property string brightnessDevice:    ""
    property bool   showSeconds:         false
    property bool   compactDate:         false
    property bool   clock12h:            false
    property bool   showWindowTitle:     false
    property bool   showWindowTitleApp:  false
    property bool   windowTitleCenterGap: true
    property bool   updatesWidget:       false
    property bool   trayWidget:          false
    property bool   valuesOnHover:       true
    property bool   hoverLevelBar:       false
    property bool   batteryAutoHide:     true
    property bool   barShowBattery:      true
    property bool   barShowNetwork:      true
    property bool   barShowClock:        true
    property bool   barShowShellUpdate:  true
    property bool   barShowVolume:       true
    property bool   barShowBrightness:   true
    property bool   barShowMedia:        true

    property bool   osdEnabled:     true
    property int    osdTimeout:     2000
    property string osdKindFilter:  "both"
    property bool   osdBatteryWarn: false
    property bool   osdTempWarn:    false
    property bool   osdVolumeTint:  false
    property bool   osdChargedNotify: false
    property bool   osdBarIntegrated: false
    property bool   osdMatchBar:      true
    property bool   reduceMotion:        false
    property bool   highContrast:        false
    property real   outlineStrength:     1.0
    property real   uiScale:             1.0
    property string fontFamily:          ""

    property bool   notifPopupEnabled:   true
    property bool   notifFullscreenSilence: true
    property string notifPosition:       "top-right"
    property int    notifMaxVisible:     3
    property bool   dndSchedule:         false
    property int    dndFrom:             22
    property int    dndTo:               8
    property string mediaWidgetFormat:   "title"
    property int    tempHotThreshold:    90
    property int    batteryLowThreshold: 20
    property int    notifDefaultTimeout: 5000
    property int    sysAlertTimeout:     10000
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
    property bool   screenshotGlowSweep:     false

    property real   dotOpacity:          0.28
    property string dotStyle:            "·"
    readonly property string dotTextGlyph: dotStyle === "|" || dotStyle === "line" ? "│"
                                         : dotStyle === "slash" ? "/"
                                         : dotStyle === "none"  ? "·"
                                         : dotStyle
    property int    barSpacing:          11
    property bool   barAutoCompact:      true
    property bool   barCompact:          false
    property bool   barHoverHighlight:   false
    property int    barHeight:           36
    property bool   barFloating:         false
    property real   barWidth:            0.90
    property string barCornerStyle:      "round"
    property int    barRadius:           14
    property bool   barShadow:           false
    property real   barShadowStrength:   1.0
    property string barPosition:         "top"
    property real   barOpacity:          0.88
    property string barDisabledMonitors: ""
    property string overlayMonitor:      ""

    readonly property var _allBarWidgetKeys: ["workspaces", "shellUpdate", "tray", "updates", "network", "volume", "brightness", "battery", "media", "clock"]

    property string barWidgetOrderLeft:  "workspaces"
    property string barWidgetOrderRight: "shellUpdate,tray,updates,network,volume,brightness,battery,media,clock"

    readonly property var _zoneKeys: {
        const all = root._allBarWidgetKeys
        const valid = {}
        for (let i = 0; i < all.length; i++) valid[all[i]] = true
        const parse = s => (s || "").split(",").map(x => x.trim()).filter(x => x.length > 0)
        const seen = {}
        const left = [], right = []
        const leftRaw = parse(root.barWidgetOrderLeft)
        for (let i = 0; i < leftRaw.length; i++) {
            const k = leftRaw[i]
            if (seen[k] || valid[k] !== true) continue
            seen[k] = true; left.push(k)
        }
        const rightRaw = parse(root.barWidgetOrderRight)
        for (let i = 0; i < rightRaw.length; i++) {
            const k = rightRaw[i]
            if (seen[k] || valid[k] !== true) continue
            seen[k] = true; right.push(k)
        }
        for (let i = 0; i < all.length; i++) {
            const k = all[i]
            if (seen[k]) continue
            if (k === "workspaces") left.push(k); else right.push(k)
        }
        const loc = {}
        for (let i = 0; i < left.length; i++) loc[left[i]] = { zone: "left", index: i }
        for (let i = 0; i < right.length; i++) loc[right[i]] = { zone: "right", index: i }
        return { left: left, right: right, loc: loc }
    }
    readonly property var barWidgetOrderLeftKeys:  root._zoneKeys.left
    readonly property var barWidgetOrderRightKeys: root._zoneKeys.right
    readonly property var _missingBarWidgetLocation: ({ zone: "", index: -1 })
    readonly property var _barWidgetLocations: root._zoneKeys.loc

    function barWidgetLocate(key: string): var {
        return root._barWidgetLocations[key] || root._missingBarWidgetLocation
    }

    function moveBarWidget(key: string, delta: int): void {
        const loc = root.barWidgetLocate(key)
        if (loc.index < 0) return
        const arr = (loc.zone === "left" ? root.barWidgetOrderLeftKeys : root.barWidgetOrderRightKeys).slice()
        const j = loc.index + delta
        if (j < 0 || j >= arr.length) return
        const t = arr[loc.index]; arr[loc.index] = arr[j]; arr[j] = t
        if (loc.zone === "left") root.barWidgetOrderLeft = arr.join(",")
        else                     root.barWidgetOrderRight = arr.join(",")
    }

    function setBarWidgetZone(key: string, zone: string, atIndex: int): void {
        if (root._allBarWidgetKeys.indexOf(key) < 0 || (zone !== "left" && zone !== "right"))
            return
        const left  = root.barWidgetOrderLeftKeys.filter(k => k !== key)
        const right = root.barWidgetOrderRightKeys.filter(k => k !== key)
        const target = (zone === "left") ? left : right
        const rawIndex = Number(atIndex)
        const clamped = isNaN(rawIndex) ? target.length : Math.max(0, Math.min(target.length, Math.round(rawIndex)))
        target.splice(clamped, 0, key)
        root.barWidgetOrderLeft  = left.join(",")
        root.barWidgetOrderRight = right.join(",")
    }

    function resetBarWidgets(): void {
        root.barWidgetOrderLeft = _defaults.barWidgetOrderLeft
        root.barWidgetOrderRight = _defaults.barWidgetOrderRight
        for (const key in root.barWidgetMeta) {
            const setting = root.barWidgetMeta[key].setting
            if (setting.length > 0) root[setting] = _defaults[setting]
        }
    }

    readonly property var barWidgetMeta: ({
        workspaces:  { glyph: "󰊗", label: "Workspaces",      group: "workspaces", setting: "" },
        shellUpdate: { glyph: "󰑐", label: "Shell update",    group: "shell",  setting: "barShowShellUpdate" },
        tray:        { glyph: "󰇘", label: "System tray",     group: "tray",   setting: "trayWidget" },
        updates:     { glyph: "󰚰", label: "Package updates", group: "status", setting: "updatesWidget" },
        network:     { glyph: "󰛳", label: "Network",         group: "status", setting: "barShowNetwork" },
        volume:      { glyph: "󰕾", label: "Volume",          group: "levels", setting: "barShowVolume" },
        brightness:  { glyph: "󰃟", label: "Brightness",      group: "levels", setting: "barShowBrightness" },
        battery:     { glyph: "󰂄", label: "Battery",         group: "levels", setting: "barShowBattery" },
        media:       { glyph: "󰝚", label: "Media",           group: "media",  setting: "barShowMedia" },
        clock:       { glyph: "󰅐", label: "Clock",           group: "clock",  setting: "barShowClock" }
    })

    property int    nightLightTemp:      3500
    property bool   nightLightAuto:     false

    property int    wsMinVisible:        5
    property bool   wsShowNumbers:       false
    property bool   wsScrollSwitch:      false
    property bool   wsShowAppIcons:      false
    property bool   wsNotifPulse:        false
    property real   wsMarkerOpacity:     1.0
    property real   wsIconOpacity:       0.68
    property bool   wsIconMono:          true
    property string wsActiveMarker:      "gem"

    property bool _loaded: false
    property bool _configDirReady: false
    property bool _savePendingForDir: false
    property int _saveFailureCount: 0
    readonly property bool ready: _loaded
    readonly property int _settingsVersion: 1
    property var _defaults: ({})
    property string _lastSavedJson: ""

    // drives load/save/change-tracking. t: bool|int|real|enum|re — int/real use min/max, enum vals, re a pattern
    readonly property var _schema: [
        { k: "mediaProgress",       t: "bool" },
        { k: "mediaWidgetHelper",   t: "bool" },
        { k: "mediaVisualizerPreset", t: "enum", vals: ["eco", "balanced", "smooth"] },
        { k: "mediaVisualizerStyle",  t: "enum", vals: ["wave", "bars", "pulse"] },
        { k: "mediaVisualizerPosition", t: "enum", vals: ["media", "center"] },
        { k: "workspaceShift",      t: "bool" },
        { k: "neutralTheme",        t: "bool" },
        { k: "neutralAccentAuto",   t: "bool" },
        { k: "neutralAccent",       t: "re",   re: /^#[0-9a-fA-F]{6}$/ },
        { k: "matugenAccentRole",   t: "enum", vals: ["primary", "secondary", "tertiary"] },
        { k: "baseTone",            t: "enum", vals: ["black", "charcoal", "graphite"] },
        { k: "networkTrafficStats", t: "bool" },
        { k: "networkSpeedInline",  t: "bool" },
        { k: "netVpnShowLink",      t: "bool" },
        { k: "brightnessDevice",    t: "re",   re: /^[A-Za-z0-9_.:+@-]*$/ },
        { k: "showSeconds",         t: "bool" },
        { k: "compactDate",         t: "bool" },
        { k: "clock12h",            t: "bool" },
        { k: "showWindowTitle",     t: "bool" },
        { k: "showWindowTitleApp",  t: "bool" },
        { k: "windowTitleCenterGap", t: "bool" },
        { k: "updatesWidget",       t: "bool" },
        { k: "trayWidget",          t: "bool" },
        { k: "valuesOnHover",       t: "bool" },
        { k: "hoverLevelBar",       t: "bool" },
        { k: "batteryAutoHide",     t: "bool" },
        { k: "barShowBattery",      t: "bool" },
        { k: "barShowNetwork",      t: "bool" },
        { k: "barShowClock",        t: "bool" },
        { k: "barShowShellUpdate",  t: "bool" },
        { k: "barShowVolume",       t: "bool" },
        { k: "barShowBrightness",   t: "bool" },
        { k: "barShowMedia",        t: "bool" },
        { k: "osdEnabled",          t: "bool" },
        { k: "osdTimeout",          t: "int",  min: 500,  max: 10000 },
        { k: "osdKindFilter",       t: "enum", vals: ["both", "volume", "brightness"] },
        { k: "osdBatteryWarn",      t: "bool" },
        { k: "osdTempWarn",         t: "bool" },
        { k: "osdVolumeTint",       t: "bool" },
        { k: "osdChargedNotify",    t: "bool" },
        { k: "osdBarIntegrated",    t: "bool" },
        { k: "osdMatchBar",         t: "bool" },
        { k: "reduceMotion",        t: "bool" },
        { k: "highContrast",        t: "bool" },
        { k: "outlineStrength",     t: "real", min: 0.5, max: 1.6 },
        { k: "uiScale",             t: "real", min: 0.8, max: 1.15 },
        { k: "fontFamily",          t: "re",   re: /^[A-Za-z0-9 ._-]*$/ },
        { k: "notifPopupEnabled",   t: "bool" },
        { k: "notifFullscreenSilence", t: "bool" },
        { k: "notifPosition",       t: "enum", vals: ["top-right", "top-left", "top-center"] },
        { k: "notifMaxVisible",     t: "int",  min: 0, max: 20 },
        { k: "dndSchedule",         t: "bool" },
        { k: "dndFrom",             t: "int",  min: 0, max: 23 },
        { k: "dndTo",               t: "int",  min: 0, max: 23 },
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
        { k: "screenshotGlowSweep", t: "bool" },
        { k: "dotOpacity",          t: "real", min: 0.05, max: 1.0 },
        { k: "dotStyle",            t: "enum", vals: ["·", "•", "◦", "|", "slash", "line", "none"] },
        { k: "barSpacing",          t: "int",  min: 4, max: 24 },
        { k: "barAutoCompact",      t: "bool" },
        { k: "barCompact",          t: "bool" },
        { k: "barHoverHighlight",   t: "bool" },
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
        { k: "barWidgetOrderLeft",  t: "re",   re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/ },
        { k: "barWidgetOrderRight", t: "re",   re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/ },

        { k: "nightLightTemp",      t: "int",  min: 1000, max: 6500 },
        { k: "nightLightAuto",     t: "bool" },
        { k: "wsMinVisible",        t: "int",  min: 1,    max: 10 },
        { k: "wsShowNumbers",       t: "bool" },
        { k: "wsScrollSwitch",      t: "bool" },
        { k: "wsShowAppIcons",      t: "bool" },
        { k: "wsNotifPulse",        t: "bool" },
        { k: "wsMarkerOpacity",     t: "real", min: 0.2, max: 1.0 },
        { k: "wsIconOpacity",       t: "real", min: 0.3, max: 1.0 },
        { k: "wsIconMono",          t: "bool" },
        { k: "wsActiveMarker",      t: "enum", vals: ["gem", "dot"] }
    ]

    function _coerce(s, v): void {
        switch (s.t) {
        case "bool":
            if (typeof v === "boolean") root[s.k] = v
            else if (v === "true" || v === "false") root[s.k] = v === "true"
            break
        case "int": {
            const n = (typeof v === "number" || (typeof v === "string" && v.trim().length > 0)) ? Number(v) : NaN
            if (isFinite(n)) root[s.k] = Math.max(s.min, Math.min(s.max, Math.round(n)))
            break
        }
        case "real": {
            const n = (typeof v === "number" || (typeof v === "string" && v.trim().length > 0)) ? Number(v) : NaN
            if (isFinite(n)) root[s.k] = Math.max(s.min, Math.min(s.max, n))
            break
        }
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
        // v0 wrote every key with no version marker; unknown/deprecated keys drop on the next _save()
        delete j.midnightNeutral
        delete j.warmNeutral
        delete j.screenshotGlowTint
        delete j.activeGlowStrength
        return j
    }

    function _onSettingChanged(): void {
        if (!_loaded) return
        _recomputeModified()
        _writeTimer.restart()
    }

    property var modifiedKeys: []
    function _recomputeModified(): void {
        const out = []
        for (let i = 0; i < _schema.length; i++) {
            const k = _schema[i].k
            if (!_sameValue(root[k], _defaults[k])) out.push(k)
        }
        if (out.join(",") !== modifiedKeys.join(",")) modifiedKeys = out
    }

    function resetKey(k: string): void {
        if (_defaults[k] !== undefined) root[k] = _defaults[k]
    }

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
            root._configDirReady = code === 0
            if (code !== 0) {
                console.warn("silere-shell: failed to create settings directory:", root._configDir)
                return
            }
            if (root._savePendingForDir) {
                root._savePendingForDir = false
                root._save()
            }
        }
    }

    FileView {
        id: _file
        path: root._configDir + "/settings.json"
        watchChanges: true
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onLoaded:      root._applyText(_file.text())
        onLoadFailed:  root._loaded = true
        onFileChanged: reload()
        onSaved: {
            root._saveFailureCount = 0
            _saveRetry.stop()
        }
        onSaveFailed: (error) => {
            // _save() records the candidate before writing so watcher echoes
            // can be ignored. Clear it on failure or the same settings would
            // be mistaken for an already-persisted value forever.
            root._lastSavedJson = ""
            root._saveFailureCount++
            console.warn("silere-shell: failed to save settings.json:", error)
            if (root._saveFailureCount <= 3) _saveRetry.restart()
        }
    }

    function _backupBeforeMigrate(raw: string, onDiskVersion: int): void {
        _backupFile.path = _configDir + "/settings.v" + onDiskVersion + ".bak.json"
        _backupFile.setText(raw)
    }

    FileView {
        id: _backupFile
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onSaveFailed: (error) => console.warn("silere-shell: failed to back up settings before migration:", error)
    }

    function _applyText(t: string): void {
        const raw = (t || "").trim()
        // our own atomic write echoes back through the watcher; skip it
        if (raw === _lastSavedJson) { _loaded = true; return }
        try {
            const parsed = JSON.parse(raw || "{}")
            if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object")
                throw new Error("settings root must be an object")
            const onDiskVersion = typeof parsed.__version === "number" ? parsed.__version : 0
            if (onDiskVersion < _settingsVersion && Object.keys(parsed).length > 0)
                _backupBeforeMigrate(raw, onDiskVersion)
            const j = _migrate(parsed)
            if (_loaded) {
                _loaded = false
                for (let i = 0; i < _schema.length; i++) {
                    const key = _schema[i].k
                    root[key] = _defaults[key]
                }
            }
            for (let i = 0; i < _schema.length; i++) {
                const s = _schema[i]
                if (j[s.k] !== undefined) _coerce(s, j[s.k])
            }
        } catch(e) { console.warn("silere-shell: failed to parse settings.json, keeping current settings:", String(e)) }
        _loaded = true
        _recomputeModified()
    }

    Timer {
        id: _writeTimer
        interval: 400
        onTriggered: root._save()
    }

    Timer {
        id: _saveRetry
        interval: Math.min(8000, 1000 * Math.pow(2, Math.max(0, root._saveFailureCount - 1)))
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
        // Alternate harmless trailing whitespace after a failed write. FileView
        // coalesces identical setText() calls, so an exact retry may otherwise
        // never reach the filesystem even though the previous save failed.
        _file.setText(j + (root._saveFailureCount % 2 === 0 ? "\n" : "\n\n"))
    }
}
