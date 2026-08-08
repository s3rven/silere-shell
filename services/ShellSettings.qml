pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property bool   mediaProgress:       false
    property bool   mediaWidgetHelper:   false
    property string mediaVisualizerPreset: "balanced"
    property string mediaVisualizerStyle:  "wave"
    property string mediaVisualizerPosition: "media"
    property bool   workspaceShift:      true
    property bool   neutralTheme:        true
    property bool   neutralAccentAuto:   false
    property string neutralAccent:       "#b8bdd8"
    property string matugenAccentRole:   "primary"
    property string matugenDepth:        "none"
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
    property bool   settingsNavPinned:   true
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

    property real   dotOpacity:          0.38
    property string dotStyle:            "line"
    readonly property string dotTextGlyph: dotStyle === "|" || dotStyle === "line" ? "│"
                                         : dotStyle === "slash" ? "/"
                                         : dotStyle === "none"  ? "·"
                                         : dotStyle
    property string barSeparatorMode:   "groups"
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

    readonly property var barWidgetKeys: ["workspaces", "shellUpdate", "tray", "updates", "network", "volume", "brightness", "battery", "media", "clock"]

    property string barWidgetOrderLeft:  "workspaces,media"
    property string barWidgetOrderCenter: ""
    property string barWidgetOrderRight: "shellUpdate,tray,updates,network,volume,brightness,battery,clock"

    function _widgetKeyList(value): var {
        const raw = Array.isArray(value) ? value : String(value || "").split(",")
        return raw.map(function(key) { return String(key).trim() })
            .filter(function(key) { return key.length > 0 })
    }

    function _normaliseBarWidgetLayout(leftValue, centerValue, rightValue): var {
        const all = root.barWidgetKeys
        const valid = {}
        for (let i = 0; i < all.length; i++) valid[all[i]] = true
        const seen = {}
        const left = [], center = [], right = []
        const leftRaw = root._widgetKeyList(leftValue)
        for (let i = 0; i < leftRaw.length; i++) {
            const k = leftRaw[i]
            if (seen[k] || valid[k] !== true) continue
            seen[k] = true; left.push(k)
        }
        const centerRaw = root._widgetKeyList(centerValue)
        for (let i = 0; i < centerRaw.length; i++) {
            const k = centerRaw[i]
            if (seen[k] || valid[k] !== true) continue
            seen[k] = true; center.push(k)
        }
        const rightRaw = root._widgetKeyList(rightValue)
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
        for (let i = 0; i < center.length; i++) loc[center[i]] = { zone: "center", index: i }
        for (let i = 0; i < right.length; i++) loc[right[i]] = { zone: "right", index: i }
        return { left: left, center: center, right: right, loc: loc }
    }
    readonly property var _zoneKeys: root._normaliseBarWidgetLayout(
        root.barWidgetOrderLeft, root.barWidgetOrderCenter, root.barWidgetOrderRight)
    readonly property var barWidgetOrderLeftKeys:  root._zoneKeys.left
    readonly property var barWidgetOrderCenterKeys: root._zoneKeys.center
    readonly property var barWidgetOrderRightKeys: root._zoneKeys.right
    readonly property var _missingBarWidgetLocation: ({ zone: "", index: -1 })
    readonly property var _barWidgetLocations: root._zoneKeys.loc

    function barWidgetLocate(key: string): var {
        return root._barWidgetLocations[key] || root._missingBarWidgetLocation
    }

    function moveBarWidget(key: string, delta: int): void {
        const loc = root.barWidgetLocate(key)
        if (loc.index < 0) return
        const arr = (loc.zone === "left" ? root.barWidgetOrderLeftKeys
            : loc.zone === "center" ? root.barWidgetOrderCenterKeys
            : root.barWidgetOrderRightKeys).slice()
        const j = loc.index + delta
        if (j < 0 || j >= arr.length) return
        const t = arr[loc.index]; arr[loc.index] = arr[j]; arr[j] = t
        if (loc.zone === "left")
            root.setBarWidgetLayout(arr, root.barWidgetOrderCenterKeys, root.barWidgetOrderRightKeys)
        else if (loc.zone === "center")
            root.setBarWidgetLayout(root.barWidgetOrderLeftKeys, arr, root.barWidgetOrderRightKeys)
        else
            root.setBarWidgetLayout(root.barWidgetOrderLeftKeys, root.barWidgetOrderCenterKeys, arr)
    }

    function setBarWidgetLayout(leftKeys, centerKeys, rightKeys): void {
        const layout = root._normaliseBarWidgetLayout(leftKeys, centerKeys, rightKeys)
        const left = layout.left.join(",")
        const center = layout.center.join(",")
        const right = layout.right.join(",")
        if (root.barWidgetOrderLeft !== left) root.barWidgetOrderLeft = left
        if (root.barWidgetOrderCenter !== center) root.barWidgetOrderCenter = center
        if (root.barWidgetOrderRight !== right) root.barWidgetOrderRight = right
    }

    function setBarWidgetZone(key: string, zone: string, atIndex: int): void {
        if (root.barWidgetKeys.indexOf(key) < 0
                || (zone !== "left" && zone !== "center" && zone !== "right"))
            return
        const left  = root.barWidgetOrderLeftKeys.filter(k => k !== key)
        const center = root.barWidgetOrderCenterKeys.filter(k => k !== key)
        const right = root.barWidgetOrderRightKeys.filter(k => k !== key)
        const target = zone === "left" ? left : zone === "center" ? center : right
        const rawIndex = Number(atIndex)
        const clamped = isNaN(rawIndex) ? target.length : Math.max(0, Math.min(target.length, Math.round(rawIndex)))
        target.splice(clamped, 0, key)
        root.setBarWidgetLayout(left, center, right)
    }

    function resetBarWidgets(): void {
        root.setBarWidgetLayout(_defaults.barWidgetOrderLeft,
            _defaults.barWidgetOrderCenter,
            _defaults.barWidgetOrderRight)
        for (const key in root.barWidgetMeta) {
            const setting = root.barWidgetMeta[key].setting
            if (setting.length > 0) root[setting] = _defaults[setting]
        }
    }

    function _barWidgetsModified(): bool {
        if (!root.ready) return false
        const current = root._normaliseBarWidgetLayout(
            root.barWidgetOrderLeft, root.barWidgetOrderCenter,
            root.barWidgetOrderRight)
        const defaults = root._normaliseBarWidgetLayout(
            root._defaults.barWidgetOrderLeft, root._defaults.barWidgetOrderCenter,
            root._defaults.barWidgetOrderRight)
        if (current.left.join(",") !== defaults.left.join(",")
                || current.center.join(",") !== defaults.center.join(",")
                || current.right.join(",") !== defaults.right.join(",")) return true
        for (const key in root.barWidgetMeta) {
            const setting = root.barWidgetMeta[key].setting
            if (setting.length > 0
                    && !root._sameValue(root[setting], root._defaults[setting])) return true
        }
        return false
    }
    readonly property bool barWidgetsModified: root._barWidgetsModified()

    readonly property var barWidgetMeta: ({
        workspaces:  { glyph: "󰊗", label: "Workspaces",      group: "workspaces", setting: "" },
        shellUpdate: { glyph: "󰑐", label: "Shell update",    group: "updates", setting: "barShowShellUpdate" },
        tray:        { glyph: "󰇘", label: "System tray",     group: "tray",    setting: "trayWidget" },
        updates:     { glyph: "󰚰", label: "Package updates", group: "updates", setting: "updatesWidget" },
        network:     { glyph: "󰛳", label: "Network",         group: "network", setting: "barShowNetwork" },
        volume:      { glyph: "󰕾", label: "Volume",          group: "levels", setting: "barShowVolume" },
        brightness:  { glyph: "󰃟", label: "Brightness",      group: "levels", setting: "barShowBrightness" },
        battery:     { glyph: "󰂄", label: "Battery",         group: "power",  setting: "barShowBattery" },
        media:       { glyph: "󰝚", label: "Media",           group: "media",  setting: "barShowMedia" },
        clock:       { glyph: "󰅐", label: "Clock",           group: "clock",  setting: "barShowClock" }
    })

    function barWidgetConfiguredVisible(key: string): bool {
        const meta = root.barWidgetMeta[key]
        if (!meta) return false
        return meta.setting.length === 0 || root[meta.setting] !== false
    }

    function setBarWidgetConfiguredVisible(key: string, visible: bool): void {
        const meta = root.barWidgetMeta[key]
        if (!meta || meta.setting.length === 0) return
        root[meta.setting] = visible
    }

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
    property string _readError: ""
    property string _writeError: ""
    property string _diskText: ""
    readonly property bool ready: _loaded
    readonly property string settingsError: ConfigStore.error.length > 0
        ? ConfigStore.error : _writeError.length > 0 ? _writeError : _readError
    readonly property int _settingsVersion: 1
    property var _defaults: ({})
    property real _loadedVersion: _settingsVersion
    property var _futureSettings: ({})
    property var _futureTouched: ({})

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
        { k: "matugenDepth",        t: "enum", vals: ["none", "deep", "deeper"] },
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
        { k: "settingsNavPinned",   t: "bool" },
        { k: "reduceMotion",        t: "bool" },
        { k: "highContrast",        t: "bool" },
        { k: "outlineStrength",     t: "real", min: 0.5, max: 2.4 },
        { k: "uiScale",             t: "real", min: 0.8, max: 1.15 },
        { k: "fontFamily",          t: "re",   re: /^[^\u0000-\u001F\u007F]{0,128}$/ },
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
        { k: "barLineStrength",     t: "real", min: 0.5, max: 3.0 },
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
        { k: "barSeparatorMode",    t: "enum", vals: ["groups", "widgets"] },
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
        { k: "barWidgetOrderCenter", t: "re", re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/ },
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
        { k: "wsActiveMarker",      t: "enum", vals: ["gem", "dot", "bar"] }
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

    property int _modifiedCount: 0
    readonly property int modifiedCount: _modifiedCount

    // recounted only on load and on the debounced save, never per keystroke
    function _recountModified(): void {
        let n = 0
        for (let i = 0; i < _schema.length; i++)
            if (!root._sameValue(root[_schema[i].k], root._defaults[_schema[i].k])) n++
        root._modifiedCount = n
    }

    function resetToDefaults(): void {
        _backupSettings("pre-reset")
        for (let i = 0; i < _schema.length; i++) {
            const k = _schema[i].k
            if (k !== "barWidgetOrderLeft" && k !== "barWidgetOrderCenter"
                    && k !== "barWidgetOrderRight")
                root[k] = _defaults[k]
        }
        // the order keys go through the normalising setter, not a raw assignment
        root.resetBarWidgets()
        root._recountModified()
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

    function _onSettingChanged(key: string): void {
        if (!_loaded || !_store.writeAllowed) return
        if (_loadedVersion > _settingsVersion) _futureTouched[key] = true
        _store.queue()
    }

    Component.onDestruction: {
        _store.stop()
        // never overwrite the file with defaults never confirmed from disk
        if (!root._loaded || !_store.writeAllowed) return
        if (!ConfigStore.ready)
            console.warn("silere-shell: saving settings before config dir is ready:",
                ConfigStore.directory)
        _store.flush(true)   // blocking write, so the reload-time save actually lands
    }

    Component.onCompleted: {
        _defaults = _captureDefaults()
        for (let i = 0; i < _schema.length; i++) {
            const key = _schema[i].k
            root[key + "Changed"].connect(function() { root._onSettingChanged(key) })
        }
        ConfigStore.ensureDirectory()
    }

    PersistedFile {
        id: _store
        path: ConfigStore.settingsPath
        watchChanges: true
        writeAllowed: false
        serialize: () => root._serialize()
        onLoaded: raw => {
            root._diskText = raw
            root._applyText(raw)
        }
        onLoadFailed: error => {
            _store.writeAllowed = error === FileViewError.FileNotFound
            root._readError = _store.writeAllowed ? ""
                : "Could not read settings.json. Existing data was left untouched."
            root._loaded = true
        }
        onSaved: {
            root._futureTouched = ({})
            root._readError = ""
            root._writeError = ""
        }
        onSaveFailed: error => {
            root._writeError = "Could not save settings. Changes may be lost."
            console.warn("silere-shell: failed to save settings.json:", error)
        }
    }

    function _backupSettings(tag: string): void {
        const body = root._diskText.trim()
        if (body.length === 0) return
        _backupFile.path = ConfigStore.directory + "/settings." + tag + ".bak.json"
        _backupFile.setText(body)
    }

    FileView {
        id: _backupFile
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onSaved: ConfigStore.hardenFile(_backupFile.path)
        onSaveFailed: (error) => console.warn("silere-shell: failed to back up settings.json:", error)
    }

    function _applyText(t: string): void {
        const raw = (t || "").trim()
        // our own atomic write echoes back through the watcher; skip it
        if (_store.writeAllowed && raw === _store.lastSavedText) { _loaded = true; return }
        try {
            const parsed = JSON.parse(raw || "{}")
            if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object")
                throw new Error("settings root must be an object")
            const rawVersion = typeof parsed.__version === "number" && isFinite(parsed.__version)
                ? parsed.__version : 0
            const onDiskVersion = Math.max(0, Math.floor(rawVersion))
            if (onDiskVersion < _settingsVersion && Object.keys(parsed).length > 0)
                _backupSettings("v" + onDiskVersion)
            const fromFuture = onDiskVersion > _settingsVersion
            _loadedVersion = fromFuture ? onDiskVersion : _settingsVersion
            _futureSettings = fromFuture ? parsed : ({})
            _futureTouched = ({})
            if (fromFuture)
                console.warn("silere-shell: settings.json is from newer version", onDiskVersion,
                    "— preserving unknown values")
            if (_loaded) {
                _loaded = false
                for (let i = 0; i < _schema.length; i++) {
                    const key = _schema[i].k
                    root[key] = _defaults[key]
                }
            }
            for (let i = 0; i < _schema.length; i++) {
                const s = _schema[i]
                if (parsed[s.k] !== undefined) _coerce(s, parsed[s.k])
            }
            root._readError = ""
            _store.writeAllowed = true
        } catch(e) {
            _store.writeAllowed = false
            root._readError = "Could not read settings.json. Current settings were kept."
            console.warn("silere-shell: failed to parse settings.json, keeping current settings:", String(e))
        }
        _loaded = true
        root._recountModified()
    }

    function _serialize(): string {
        const preserveFuture = _loadedVersion > _settingsVersion
        const out = preserveFuture
            ? JSON.parse(JSON.stringify(_futureSettings)) : ({})
        out.__version = preserveFuture ? _loadedVersion : _settingsVersion
        let changed = 0
        for (let i = 0; i < _schema.length; i++) {
            const key = _schema[i].k
            const modified = !root._sameValue(root[key], root._defaults[key])
            if (modified) {
                out[key] = root[key]
                changed++
            } else if (!preserveFuture || root._futureTouched[key] === true) {
                delete out[key]
            }
        }
        root._modifiedCount = changed
        if (preserveFuture) _futureSettings = out
        return JSON.stringify(out, null, 2)
    }
}
