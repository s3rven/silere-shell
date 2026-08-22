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
    property string neutralAccent:       "#9babe9"
    property string matugenAccentRole:   "primary"
    property string matugenDepth:        "deeper"
    property string baseTone:            "black"
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
    property bool   updatesIncludeAur:   false
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
    property bool   osdChargedNotify: false
    property bool   osdBarIntegrated: false
    property bool   osdMatchBar:      true
    property bool   settingsNavPinned:   false
    property bool   settingsNavDots:     true
    property bool   reduceMotion:        false
    property bool   highContrast:        false
    property real   outlineStrength:     1.0
    property real   uiScale:             1.0
    property string fontFamily:          ""

    property bool   notifPopupEnabled:   true
    property bool   notifFullscreenSilence: true
    property string notifPosition:       "top-right"
    property int    notifMaxVisible:     3
    property bool   notifHistoryPersistent: true
    property int    notifHistoryLimit:   20
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
    property string underlineLastStyle:  "static"
    property bool   underlineIdleGlow:   false
    property bool   underlineFullWidth:  false
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
    property int    barIconSize:         12
    property bool   barFloating:         false
    property int    barGap:              4
    property real   barWidth:            0.90
    property int    barRadius:           14
    property bool   barShadow:           false
    property real   barShadowStrength:   1.0
    property string barPosition:         "top"
    property real   barOpacity:          0.88
    property bool   popupMatchBarOpacity: false
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
        const zones = [left, center, right]
        const values = [leftValue, centerValue, rightValue]
        for (let zone = 0; zone < zones.length; zone++) {
            const keys = root._widgetKeyList(values[zone])
            for (let i = 0; i < keys.length; i++) {
                const key = keys[i]
                if (seen[key] || valid[key] !== true) continue
                seen[key] = true
                zones[zone].push(key)
            }
        }
        for (let i = 0; i < all.length; i++) {
            const k = all[i]
            if (seen[k]) continue
            if (k === "workspaces") left.push(k); else right.push(k)
        }
        const loc = {}
        const names = ["left", "center", "right"]
        for (let zone = 0; zone < zones.length; zone++)
            for (let i = 0; i < zones[zone].length; i++)
                loc[zones[zone][i]] = { zone: names[zone], index: i }
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

    function setBarWidgetLayout(leftKeys, centerKeys, rightKeys): void {
        const layout = root._normaliseBarWidgetLayout(leftKeys, centerKeys, rightKeys)
        const left = layout.left.join(",")
        const center = layout.center.join(",")
        const right = layout.right.join(",")
        if (root.barWidgetOrderLeft !== left) root.barWidgetOrderLeft = left
        if (root.barWidgetOrderCenter !== center) root.barWidgetOrderCenter = center
        if (root.barWidgetOrderRight !== right) root.barWidgetOrderRight = right
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
        // no setting: the diamond is the only way into the menu, so this one cannot be hidden
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
    property bool   wsUrgentPulse:       true
    property real   wsMarkerOpacity:     1.0
    property real   wsIconOpacity:       0.68
    property bool   wsIconMono:          true
    property string wsActiveMarker:      "gem"

    property bool _loaded: false
    property string _readError: ""
    property string _writeError: ""
    property string _diskText: ""
    property string _appliedText: ""
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
        { k: "mediaProgress",       t: "bool", sec: "media" },
        { k: "mediaWidgetHelper",   t: "bool", sec: "media" },
        { k: "mediaVisualizerPreset", t: "enum", vals: ["eco", "balanced", "smooth"], sec: "media" },
        { k: "mediaVisualizerStyle",  t: "enum", vals: ["wave", "bars", "pulse"], sec: "media" },
        { k: "mediaVisualizerPosition", t: "enum", vals: ["media", "center"], sec: "media" },
        { k: "workspaceShift",      t: "bool", sec: "workspaces" },
        { k: "neutralTheme",        t: "bool", sec: "theme" },
        { k: "neutralAccentAuto",   t: "bool", sec: "theme" },
        { k: "neutralAccent",       t: "re",   re: /^#[0-9a-fA-F]{6}$/, sec: "theme" },
        { k: "matugenAccentRole",   t: "enum", vals: ["primary", "secondary", "tertiary"], sec: "theme" },
        { k: "matugenDepth",        t: "enum", vals: ["none", "deep", "deeper"], sec: "theme" },
        { k: "baseTone",            t: "enum", vals: ["black", "charcoal", "graphite"], sec: "theme" },
        { k: "networkTrafficStats", t: "bool", sec: "indicators" },
        { k: "networkSpeedInline",  t: "bool", sec: "indicators" },
        { k: "netVpnShowLink",      t: "bool", sec: "indicators" },
        { k: "brightnessDevice",    t: "re",   re: /^[A-Za-z0-9_.:+@-]*$/, sec: "interface" },
        { k: "showSeconds",         t: "bool", sec: "clock" },
        { k: "compactDate",         t: "bool", sec: "clock" },
        { k: "clock12h",            t: "bool", sec: "clock" },
        { k: "showWindowTitle",     t: "bool", sec: "indicators" },
        { k: "showWindowTitleApp",  t: "bool", sec: "indicators" },
        { k: "windowTitleCenterGap", t: "bool", sec: "indicators" },
        { k: "updatesWidget",       t: "bool", sec: "widgets" },
        { k: "updatesIncludeAur",   t: "bool", sec: "updates" },
        { k: "trayWidget",          t: "bool", sec: "widgets" },
        { k: "valuesOnHover",       t: "bool", sec: "indicators" },
        { k: "hoverLevelBar",       t: "bool", sec: "indicators" },
        { k: "batteryAutoHide",     t: "bool", sec: "indicators" },
        { k: "barShowBattery",      t: "bool", sec: "widgets" },
        { k: "barShowNetwork",      t: "bool", sec: "widgets" },
        { k: "barShowClock",        t: "bool", sec: "widgets" },
        { k: "barShowShellUpdate",  t: "bool", sec: "widgets" },
        { k: "barShowVolume",       t: "bool", sec: "widgets" },
        { k: "barShowBrightness",   t: "bool", sec: "widgets" },
        { k: "barShowMedia",        t: "bool", sec: "widgets" },
        { k: "osdEnabled",          t: "bool", sec: "osd" },
        { k: "osdTimeout",          t: "int",  min: 500,  max: 10000, sec: "osd" },
        { k: "osdKindFilter",       t: "enum", vals: ["both", "volume", "brightness"], sec: "osd" },
        { k: "osdBatteryWarn",      t: "bool", sec: "warnings" },
        { k: "osdTempWarn",         t: "bool", sec: "warnings" },
        { k: "osdChargedNotify",    t: "bool", sec: "warnings" },
        { k: "osdBarIntegrated",    t: "bool", sec: "osd" },
        { k: "osdMatchBar",         t: "bool", sec: "osd" },
        { k: "settingsNavPinned",   t: "bool", sec: "interface" },
        { k: "settingsNavDots",     t: "bool", sec: "interface" },
        { k: "reduceMotion",        t: "bool", sec: "interface" },
        { k: "highContrast",        t: "bool", sec: "interface" },
        { k: "outlineStrength",     t: "real", min: 0.5, max: 2.4, sec: "theme" },
        { k: "uiScale",             t: "real", min: 0.8, max: 1.15, sec: "interface" },
        { k: "fontFamily",          t: "re",   re: /^[^\u0000-\u001F\u007F]{0,128}$/, sec: "interface" },
        { k: "notifPopupEnabled",   t: "bool", sec: "popups" },
        { k: "notifFullscreenSilence", t: "bool", sec: "popups" },
        { k: "notifPosition",       t: "enum", vals: ["top-right", "top-left", "top-center"], sec: "popups" },
        { k: "notifMaxVisible",     t: "int",  min: 0, max: 20, sec: "popups" },
        { k: "notifHistoryPersistent", t: "bool", sec: "popups" },
        { k: "notifHistoryLimit",   t: "int",  min: 5, max: 100, sec: "popups" },
        { k: "dndSchedule",         t: "bool", sec: "popups" },
        { k: "dndFrom",             t: "int",  min: 0, max: 23, sec: "popups" },
        { k: "dndTo",               t: "int",  min: 0, max: 23, sec: "popups" },
        { k: "mediaWidgetFormat",   t: "enum", vals: ["title", "artist-title"], sec: "media" },
        { k: "tempHotThreshold",    t: "int",  min: 50,   max: 105, sec: "warnings" },
        { k: "batteryLowThreshold", t: "int",  min: 5,    max: 50, sec: "warnings" },
        { k: "notifDefaultTimeout", t: "int",  min: 1000, max: 30000, sec: "popups" },
        { k: "sysAlertTimeout",     t: "int",  min: 0,    max: 30000, sec: "warnings" },
        { k: "clockShowDate",       t: "bool", sec: "clock" },
        { k: "barBorderVisible",    t: "bool", sec: "underline" },
        { k: "barLineStrength",     t: "real", min: 0.5, max: 3.0, sec: "underline" },
        { k: "underlineGlow",       t: "bool", sec: "underline" },
        { k: "underlineLastStyle",  t: "enum", vals: ["static", "glow"], sec: "underline" },
        { k: "underlineIdleGlow",   t: "bool", sec: "underline" },
        { k: "underlineFullWidth",  t: "bool", sec: "underline" },
        { k: "underlineNotifGlow",  t: "bool", sec: "underline" },
        { k: "underlineBattGlow",   t: "bool", sec: "underline,warnings" },
        { k: "underlineNetGlow",    t: "bool", sec: "underline" },
        { k: "underlineTempGlow",   t: "bool", sec: "underline,warnings" },
        { k: "underlineScreenshotGlow", t: "bool", sec: "underline" },
        { k: "glowStrength",        t: "real", min: 0.5, max: 1.75, sec: "underline" },
        { k: "screenshotGlowSweep", t: "bool", sec: "underline" },
        { k: "dotOpacity",          t: "real", min: 0.1,  max: 1.0, sec: "separators" },
        { k: "dotStyle",            t: "enum", vals: ["·", "•", "◦", "|", "slash", "line", "none"], sec: "separators" },
        { k: "barSeparatorMode",    t: "enum", vals: ["groups", "widgets"], sec: "separators" },
        { k: "barSpacing",          t: "int",  min: 4, max: 24, sec: "separators" },
        { k: "barAutoCompact",      t: "bool", sec: "separators" },
        { k: "barCompact",          t: "bool", sec: "separators" },
        { k: "barHoverHighlight",   t: "bool", sec: "indicators" },
        { k: "barHeight",           t: "int",  min: 24,   max: 60, sec: "surface" },
        { k: "barIconSize",        t: "int",  min: 10,   max: 20, sec: "interface" },
        { k: "barFloating",         t: "bool", sec: "surface" },
        { k: "barGap",              t: "int",  min: 0,    max: 24, sec: "surface" },
        { k: "barWidth",            t: "real", min: 0.5,  max: 1.0, sec: "surface" },
        { k: "barRadius",           t: "int",  min: 0,    max: 28, sec: "surface" },
        { k: "barShadow",           t: "bool", sec: "theme" },
        { k: "barShadowStrength",   t: "real", min: 0.3,  max: 1.6, sec: "theme" },
        { k: "barPosition",         t: "enum", vals: ["top", "bottom"], sec: "surface" },
        { k: "barOpacity",          t: "real", min: 0.4,  max: 1.0, sec: "surface" },
        { k: "popupMatchBarOpacity", t: "bool", sec: "surface" },
        { k: "barDisabledMonitors", t: "re",   re: /^[A-Za-z0-9._,-]*$/, sec: "interface" },
        { k: "overlayMonitor",      t: "re",   re: /^[A-Za-z0-9._-]*$/, sec: "interface" },
        { k: "barWidgetOrderLeft",  t: "re",   re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/, sec: "widgets" },
        { k: "barWidgetOrderCenter", t: "re", re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/, sec: "widgets" },
        { k: "barWidgetOrderRight", t: "re",   re: /^[a-zA-Z]*(,[a-zA-Z]+)*$/, sec: "widgets" },

        { k: "nightLightTemp",      t: "int",  min: 1000, max: 6500, sec: "-" },
        { k: "nightLightAuto",     t: "bool", sec: "-" },
        { k: "wsMinVisible",        t: "int",  min: 1,    max: 10, sec: "workspaces" },
        { k: "wsShowNumbers",       t: "bool", sec: "workspaces" },
        { k: "wsScrollSwitch",      t: "bool", sec: "workspaces" },
        { k: "wsShowAppIcons",      t: "bool", sec: "workspaces" },
        { k: "wsNotifPulse",        t: "bool", sec: "workspaces" },
        { k: "wsUrgentPulse",       t: "bool", sec: "workspaces" },
        { k: "wsMarkerOpacity",     t: "real", min: 0.2, max: 1.0, sec: "workspaces" },
        { k: "wsIconOpacity",       t: "real", min: 0.3, max: 1.0, sec: "workspaces" },
        { k: "wsIconMono",          t: "bool", sec: "workspaces" },
        { k: "wsActiveMarker",      t: "enum", vals: ["gem", "dot", "bar"], sec: "workspaces" }
    ]
    // a settings row binds by key: the schema already states type and range, so a
    // row that restates them is duplication the two can drift apart on
    function schemaFor(key: string): var {
        for (let i = 0; i < root._schema.length; i++)
            if (root._schema[i].k === key) return root._schema[i]
        return null
    }

    function setValue(key: string, value): bool {
        const entry = root.schemaFor(key)
        return entry ? root._coerce(entry, value) : false
    }

    function _coerce(s, v): bool {
        switch (s.t) {
        case "bool":
            if (typeof v === "boolean") root[s.k] = v
            else if (v === "true" || v === "false") root[s.k] = v === "true"
            else return false
            return true
        case "int": {
            const n = (typeof v === "number" || (typeof v === "string" && v.trim().length > 0)) ? Number(v) : NaN
            if (!isFinite(n)) return false
            root[s.k] = Math.max(s.min, Math.min(s.max, Math.round(n)))
            return true
        }
        case "real": {
            const n = (typeof v === "number" || (typeof v === "string" && v.trim().length > 0)) ? Number(v) : NaN
            if (!isFinite(n)) return false
            root[s.k] = Math.max(s.min, Math.min(s.max, n))
            return true
        }
        case "enum": if (s.vals.indexOf(v) >= 0) { root[s.k] = v; return true } return false
        case "re":   if (typeof v === "string" && s.re.test(v)) { root[s.k] = v; return true } return false
        }
        return false
    }

    function constraintOf(key: string): string {
        const s = root.schemaFor(key)
        if (!s) return ""
        switch (s.t) {
        case "bool": return "true|false"
        case "int":
        case "real": return s.min + ".." + s.max
        case "enum": return s.vals.join("|")
        case "re":   return String(s.re)
        }
        return ""
    }

    IpcHandler {
        target: "settings"

        function get(key: string): string {
            if (!root.schemaFor(key)) return "unknown setting '" + key + "'; try `list`"
            return String(root[key])
        }

        function set(key: string, value: string): string {
            if (!root.schemaFor(key)) return "unknown setting '" + key + "'; try `list`"
            if (!root.setValue(key, value))
                return "'" + value + "' is not valid for " + key
                    + "; expected " + root.constraintOf(key)
            return String(root[key])
        }

        function toggle(key: string): string {
            const s = root.schemaFor(key)
            if (!s) return "unknown setting '" + key + "'; try `list`"
            if (s.t !== "bool")
                return key + " is not a toggle; expected " + root.constraintOf(key)
            root[key] = !root[key]
            return String(root[key])
        }

        function list(filter: string): string {
            const want = String(filter || "").trim()
            const out = []
            for (let i = 0; i < root._schema.length; i++) {
                const s = root._schema[i]
                if (want.length > 0 && s.sec.indexOf(want) < 0 && s.k.indexOf(want) < 0)
                    continue
                out.push(s.k + "=" + String(root[s.k])
                    + "  [" + root.constraintOf(s.k) + "]")
            }
            if (out.length > 0) return out.join("\n")
            return "nothing matches '" + want + "'"
        }

        function modified(): string {
            const keys = Object.keys(root._modifiedKeys).sort()
            if (keys.length === 0) return "every setting is at its default"
            const out = []
            for (let i = 0; i < keys.length; i++)
                out.push(keys[i] + "=" + String(root[keys[i]]))
            return out.join("\n")
        }
    }

    property int _modifiedCount: 0
    property var _modifiedKeys: Object.create(null)
    // Quickshell exits hard on SIGTERM: neither Component.onDestruction nor
    // Qt.application.aboutToQuit runs, so anything still inside PersistedFile's
    // debounce window is lost on logout. Toggles and chips change at human pace,
    // so they write straight through; sliders and the hue strip keep the debounce.
    property var _discreteKeys: Object.create(null)
    // reset assigns every key at once; one write at the end, not one per toggle
    property bool _bulkAssign: false
    readonly property int modifiedCount: _modifiedCount

    property var _modifiedSections: Object.create(null)
    readonly property var modifiedSections: _modifiedSections

    readonly property var _sectionOf: {
        const m = Object.create(null)
        for (let i = 0; i < _schema.length; i++) m[_schema[i].k] = _schema[i].sec
        return m
    }

    // reassigned, never mutated: the nav reads this through a binding, and a mutation
    // would leave every dot showing whatever the set held when the page was built
    function _rebuildModifiedSections(): void {
        const secs = Object.create(null)
        for (const key in root._modifiedKeys) {
            // "-" is a key controlled from somewhere other than a settings page
            const sec = root._sectionOf[key]
            if (!sec || sec === "-") continue
            const parts = sec.split(",")
            for (let i = 0; i < parts.length; i++) secs[parts[i]] = true
        }
        root._modifiedSections = secs
    }

    function _recountModified(): void {
        let n = 0
        const keys = Object.create(null)
        for (let i = 0; i < _schema.length; i++) {
            const key = _schema[i].k
            if (root._sameValue(root[key], root._defaults[key])) continue
            keys[key] = true
            n++
        }
        root._modifiedKeys = keys
        root._modifiedCount = n
        root._rebuildModifiedSections()
    }

    function _backupStamp(): string {
        const d = new Date()
        const p = (n) => (n < 10 ? "0" : "") + n
        return "" + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate())
            + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
    }

    // one user action that moves several keys is still one settings change: without
    // this each discrete key flushes the whole file on its own
    function batch(apply): void {
        if (root._bulkAssign) { apply(); return }
        root._bulkAssign = true
        try { apply() } finally { root._bulkAssign = false }
        _store.flush(false)
    }

    function resetToDefaults(): void {
        // Capture the values visible in the UI, including changes still inside
        // PersistedFile's debounce window, rather than the older disk echo.
        // Stamped: a fixed name let a second reset overwrite the backup of the first.
        _backupSettingsText("pre-reset-" + root._backupStamp(), root._serialize())
        ConfigStore.pruneBackups()
        root._bulkAssign = true
        for (let i = 0; i < _schema.length; i++) {
            const k = _schema[i].k
            if (k !== "barWidgetOrderLeft" && k !== "barWidgetOrderCenter"
                    && k !== "barWidgetOrderRight")
                root[k] = _defaults[k]
        }
        // the order keys go through the normalising setter, not a raw assignment
        root.resetBarWidgets()
        root._bulkAssign = false
        _store.flush(false)
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
        if (!_loaded) return
        // Sliders can emit dozens of changes per second. Track the one key
        // that moved instead of rescanning the entire schema on every tick.
        const modified = !root._sameValue(root[key], root._defaults[key])
        const wasModified = root._modifiedKeys[key] === true
        if (modified !== wasModified) {
            if (modified) root._modifiedKeys[key] = true
            else delete root._modifiedKeys[key]
            root._modifiedCount += modified ? 1 : -1
            // only when a key crosses its default, not on every slider tick
            root._rebuildModifiedSections()
        }
        if (!_store.writeAllowed) return
        if (_loadedVersion > _settingsVersion) _futureTouched[key] = true
        if (!root._bulkAssign && root._discreteKeys[key] === true) _store.flush(false)
        else _store.queue()
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
            const s = _schema[i]
            const key = s.k
            if (s.t === "bool" || s.t === "enum") root._discreteKeys[key] = true
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

    function _backupSettingsText(tag: string, text: string): void {
        const body = (text || "").trim()
        if (body.length === 0) return
        _backupFile.path = ConfigStore.directory + "/settings." + tag + ".bak.json"
        _backupFile.setText(body)
    }

    function _backupSettings(tag: string): void {
        root._backupSettingsText(tag, root._diskText)
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
        if (_store.writeAllowed && raw === _store.lastSavedText) {
            root._appliedText = raw
            _loaded = true
            return
        }
        // the startup chmod trips the watcher too: re-running the reload path below would bounce
        // every setting through its default and back, rebuilding the bar on the way
        if (_loaded && raw === root._appliedText) return
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
            // The two legacy booleans represent one mode. Prefer reactive if
            // hand-edited JSON enables both, and seed the persisted restore mode
            // for settings files written before underlineLastStyle existed.
            if (root.underlineGlow && root.barBorderVisible)
                root.barBorderVisible = false
            if (root.underlineGlow) root.underlineLastStyle = "glow"
            else if (root.barBorderVisible) root.underlineLastStyle = "static"
            // barCornerStyle folded into barRadius, where 0 is flat; carry the old choice over
            if (parsed.barCornerStyle === "flat") root.barRadius = 0
            root._appliedText = raw
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
        const modifiedKeys = Object.create(null)
        for (let i = 0; i < _schema.length; i++) {
            const key = _schema[i].k
            if (!root._sameValue(root[key], root._defaults[key])) {
                out[key] = root[key]
                modifiedKeys[key] = true
                changed++
            } else if (!preserveFuture || root._futureTouched[key] === true) {
                delete out[key]
            }
        }
        root._modifiedKeys = modifiedKeys
        root._modifiedCount = changed
        root._rebuildModifiedSections()
        if (preserveFuture) _futureSettings = out
        return JSON.stringify(out, null, 2)
    }
}
