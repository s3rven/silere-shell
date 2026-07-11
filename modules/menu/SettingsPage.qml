pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"

PageShell {
    id: root

    implicitHeight: _detail.height
    scaleFrom: 0.985
    enterFade: 145; enterScale: 165; exitFade: 110
    scaleEasing: Easing.OutQuart

    function _hex2(v) {
        const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    // lags behind MenuState.settingsSection during the swap; detail pane renders whichever section this points at
    property string _shownSection: MenuState.settingsSection

    readonly property var _sectionComponents: ({
        theme: _secTheme, nightlight: _secNightLight, surface: _secSurface,
        separators: _secSeparators, underline: _secUnderline, clock: _secClock,
        workspaces: _secWorkspaces, media: _secMedia, indicators: _secIndicators,
        popups: _secPopups, osd: _secOsd, warnings: _secWarnings,
        updates: _secUpdates, system: _secSystem
    })

    // theme-section reveal state; lives here (not in the section component) so it survives section switches
    property bool _themeShowNeutral: false
    property bool _themeShowMatu:    false
    Component.onCompleted: {
        root._themeShowNeutral = ShellSettings.neutralTheme
        root._themeShowMatu    = !ShellSettings.neutralTheme
    }
    Connections {
        target: ShellSettings
        function onNeutralThemeChanged() {
            if (ShellSettings.reduceMotion) {
                root._themeShowNeutral = ShellSettings.neutralTheme
                root._themeShowMatu    = !ShellSettings.neutralTheme
                return
            }
            if (ShellSettings.neutralTheme) {
                _themeOpenMatuTimer.stop()
                root._themeShowMatu    = false
                _themeOpenNeutralTimer.restart()
            } else {
                _themeOpenNeutralTimer.stop()
                root._themeShowNeutral = false
                _themeOpenMatuTimer.restart()
            }
        }
    }
    Timer { id: _themeOpenNeutralTimer; interval: Motion.fast + 20; onTriggered: root._themeShowNeutral = true }
    Timer { id: _themeOpenMatuTimer;    interval: Motion.fast + 20; onTriggered: root._themeShowMatu    = true }

    // section id → { glyph, label, group }, for the detail-pane page header.
    readonly property var _sectionMeta: {
        const m = ({})
        const tree = MenuState.settingsTree
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
            if (it.children) {
                for (let j = 0; j < it.children.length; j++) {
                    const c = it.children[j]
                    m[c.section] = { glyph: c.glyph, label: c.label }
                }
            } else {
                m[it.section] = { glyph: it.glyph, label: it.label }
            }
        }
        return m
    }

    readonly property string _battAlertMode: {
        const o = ShellSettings.osdBatteryWarn
        const g = ShellSettings.underlineBattGlow && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setBattAlert(v) {
        ShellSettings.osdBatteryWarn = (v === "osd" || v === "both")
        ShellSettings.underlineBattGlow = (v === "glow" || v === "both")
    }

    readonly property string _tempAlertMode: {
        const o = ShellSettings.osdTempWarn
        const g = ShellSettings.underlineTempGlow && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setTempAlert(v) {
        ShellSettings.osdTempWarn = (v === "osd" || v === "both")
        ShellSettings.underlineTempGlow = (v === "glow" || v === "both")
    }

    readonly property var _alertChipModel: ShellSettings.underlineGlow
        ? [
            { value: "off",  label: "Off"  },
            { value: "osd",  label: "OSD"  },
            { value: "glow", label: "Glow" },
            { value: "both", label: "Both" }
        ]
        : [
            { value: "off", label: "Off" },
            { value: "osd", label: "OSD" }
          ]

    readonly property string _underlineScreenshotStyle:
        !ShellSettings.underlineScreenshotGlow ? "off"
        : ShellSettings.screenshotGlowSweep ? "sweep"
        : "flash"

    function _setUnderlineScreenshotStyle(style) {
        ShellSettings.underlineScreenshotGlow = style !== "off"
        ShellSettings.screenshotGlowSweep = style === "sweep"
    }

    readonly property bool _underlineEnabled:
        ShellSettings.barBorderVisible || ShellSettings.underlineGlow
    property string _lastUnderlineStyle:
        ShellSettings.underlineGlow ? "glow" : "static"
    readonly property string _underlineStyle:
        ShellSettings.underlineGlow ? "glow" : "static"

    function _setUnderlineEnabled(enabled) {
        if (!enabled) {
            root._lastUnderlineStyle = root._underlineStyle
            ShellSettings.barBorderVisible = false
            ShellSettings.underlineGlow = false
            return
        }
        root._setUnderlineStyle(root._lastUnderlineStyle)
    }

    function _setUnderlineStyle(style) {
        root._lastUnderlineStyle = style
        ShellSettings.barBorderVisible = style === "static"
        ShellSettings.underlineGlow = style === "glow"
        if (style === "glow" && !ShellSettings.underlineIdleGlow
                && !ShellSettings.underlineNotifGlow
                && !ShellSettings.underlineBattGlow
                && !ShellSettings.underlineNetGlow
                && !ShellSettings.underlineTempGlow
                && !ShellSettings.underlineScreenshotGlow) {
            ShellSettings.underlineNotifGlow = true
            ShellSettings.underlineNetGlow = true
        }
    }

    Item {
        id: _detail
        width:  root.width
        height: _detailHeader.height + _bodyGap + _detailBody.height

        readonly property int _bodyGap: 8

        property real _slide: 0
        // whole pixels only: native-rendered text shimmers on fractional translates
        transform: Translate { y: Math.round(_detail._slide) }

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (ShellSettings.reduceMotion) {
                    root._shownSection = MenuState.settingsSection
                    _detail.opacity = 1
                    _detail._slide = 0
                    return
                }
                if (!_detailSwap.running) _detailSwap.restart()
            }
        }

        SequentialAnimation {
            id: _detailSwap
            NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.ms(60); easing.type: Easing.InCubic }
            ScriptAction    { script: { root._shownSection = MenuState.settingsSection; _detail._slide = 8 } }
            ParallelAnimation {
                NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.ms(120); easing.type: Easing.OutCubic }
                NumberAnimation { target: _detail; property: "_slide";  to: 0.0; duration: Motion.ms(120); easing.type: Easing.OutQuart }
            }
            ScriptAction { script: if (root._shownSection !== MenuState.settingsSection) _detailSwapAgain.restart() }
        }
        Timer {
            id: _detailSwapAgain
            interval: 0
            onTriggered: if (!ShellSettings.reduceMotion && root._shownSection !== MenuState.settingsSection) _detailSwap.restart()
        }

            Item {
                id: _detailHeader
                width: parent.width
                height: 32
                readonly property var _meta: root._sectionMeta[root._shownSection]
                                            ?? ({ glyph: "", label: "" })

                // compact section title: no badge or rule, the card below supplies the structure
                Item {
                    id: _hdrIconSlot
                    anchors.left:           parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width:  24
                    height: 24
                    Text {
                        anchors.centerIn: parent
                        text:           _detailHeader._meta.glyph
                        color:          Theme.withAlpha(Theme.menuTextMuted, 0.92)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize + 1
                        renderType:     Text.NativeRendering
                    }
                }
                Text {
                    id: _hdrTitle
                    anchors.left:           _hdrIconSlot.right
                    anchors.leftMargin:     9
                    anchors.right:          parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text:           _detailHeader._meta.label
                    color:          Theme.text
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize + 3
                    font.weight:    Font.DemiBold
                    renderType:     Text.NativeRendering
                    elide:          Text.ElideRight
                }
            }

            // one loader for all sections: only the visible one exists, swapped while the pane sits at opacity 0
            Loader {
                id: _detailBody
                y:      _detailHeader.height + _detail._bodyGap
                width:  parent.width
                sourceComponent: root._sectionComponents[root._shownSection] ?? _secSystem

                Component {
                    id: _secTheme
                    Column {
                    width: _detailBody.width
                    spacing: 0

                    SettingsCard {
                        ChoiceChipRow {
                            glyph: "󰉦"; label: "Source"
                            currentValue: ShellSettings.neutralTheme ? "neutral" : "wallpaper"
                            model: [
                                { value: "neutral",   label: "Neutral"   },
                                { value: "wallpaper", label: "Wallpaper" }
                            ]
                            onChosen: (v) => ShellSettings.neutralTheme = (v === "neutral")
                        }

                    CollapsibleSection {
                        expanded: root._themeShowNeutral

                        Item {
                            id: _accentPicker
                            width: parent.width
                            height: 96

                            readonly property real _accentL: 0.70
                            function _accentForHS(h, s) {
                                const c = Qt.hsla(h, s, _accentL, 1.0)
                                return "#" + root._hex2(c.r) + root._hex2(c.g) + root._hex2(c.b)
                            }
                            readonly property color _curColor: ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent
                            readonly property real  _curHue:   _curColor.hslHue < 0 ? 0 : _curColor.hslHue
                            readonly property real  _curSat:   isNaN(_curColor.hslSaturation) ? 0.72 : _curColor.hslSaturation

                            // auto leads the presets so one repeater drives both the row and the sliding ring
                            readonly property var _options: [
                                { auto: true,  color: "",        name: "Auto"   },
                                { auto: false, color: "#b8bdd8", name: "Mist"   },
                                { auto: false, color: "#82aee5", name: "Blue"   },
                                { auto: false, color: "#b79bd7", name: "Violet" },
                                { auto: false, color: "#78bfb5", name: "Teal"   },
                                { auto: false, color: "#94bd8b", name: "Green"  },
                                { auto: false, color: "#dd92a2", name: "Rose"   },
                                { auto: false, color: "#d4ad77", name: "Amber"  }
                            ]
                            readonly property int _activeIndex: {
                                if (ShellSettings.neutralAccentAuto) return 0
                                for (let i = 1; i < _options.length; i++)
                                    if (_options[i].color === ShellSettings.neutralAccent) return i
                                return -1
                            }

                            readonly property var _swColors: _options.map(o => o.auto ? MatugenTheme.accent : o.color)
                            readonly property string _activeName: _activeIndex >= 0 ? _options[_activeIndex].name : "Custom"
                            readonly property string _shownName: _swatchRow.hoveredIndex >= 0 ? _options[_swatchRow.hoveredIndex].name : _activeName
                            readonly property color  _shownColor: _swatchRow.hoveredIndex >= 0 ? _swColors[_swatchRow.hoveredIndex] : _curColor

                            property real topRadius: 0
                            property real bottomRadius: 0
                            property real cardInset: 1

                            Text {
                                id: _accentTitle
                                anchors.top:            parent.top; anchors.topMargin: 11
                                anchors.left:           parent.left; anchors.leftMargin: 12
                                anchors.right:          _accentReadout.left; anchors.rightMargin: 10
                                text:           "Accent"
                                color:          Theme.withAlpha(Theme.text, 0.85)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize
                                renderType:     Text.NativeRendering
                                elide:          Text.ElideRight
                            }
                            Text {
                                id: _accentReadout
                                anchors.top:            _accentTitle.top
                                anchors.right:          parent.right; anchors.rightMargin: 12
                                width:                  Math.min(176, Math.max(96, parent.width - 110))
                                horizontalAlignment:    Text.AlignRight
                                text:           _accentPicker._shownName
                                color:          ShellSettings.highContrast
                                    ? Theme.withAlpha(Theme.subtext, 0.7)
                                    : Theme.mix(Theme.subtext, _accentPicker._shownColor, 0.62)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType:     Text.NativeRendering
                                elide:          Text.ElideRight
                            }

                            SwatchRow {
                                id: _swatchRow
                                anchors.top:        parent.top
                                anchors.topMargin:  32
                                anchors.left:       parent.left;  anchors.leftMargin:  12
                                anchors.right:      parent.right; anchors.rightMargin: 12
                                height: 32
                                spread: true
                                options: _accentPicker._options
                                colors:  _accentPicker._swColors
                                activeIndex: _accentPicker._activeIndex
                                onPicked: (i) => {
                                    if (_accentPicker._options[i].auto) {
                                        ShellSettings.neutralAccentAuto = true
                                    } else {
                                        ShellSettings.neutralAccentAuto = false
                                        ShellSettings.neutralAccent = _accentPicker._options[i].color
                                    }
                                }
                            }

                            HueStrip {
                                id: _hueStrip
                                anchors.top:       _swatchRow.bottom; anchors.topMargin: 8
                                anchors.left:      parent.left;  anchors.leftMargin:  12
                                anchors.right:     parent.right; anchors.rightMargin: 12
                                height: 12
                                hue: _accentPicker._curHue
                                saturation: 0.72
                                lightness: _accentPicker._accentL
                                thumbColor: _accentPicker._curColor
                                dimmed: ShellSettings.neutralAccentAuto
                                accessibleName: "Accent hue"
                                accessibleDescription: _accentPicker._shownName
                                onPicked: hue => {
                                    ShellSettings.neutralAccentAuto = false
                                    ShellSettings.neutralAccent = _accentPicker._accentForHS(hue, _accentPicker._curSat)
                                }
                            }
                        }

                        SwatchPickerRow {
                            glyph: "󰏘"; label: "Base tone"
                            options: [
                                { value: "black",    name: "Black"    },
                                { value: "charcoal", name: "Charcoal" },
                                { value: "graphite", name: "Graphite" }
                            ]
                            colors: ["#111216", "#191b21", "#20232b"]
                            activeIndex: options.findIndex(o => o.value === ShellSettings.baseTone)
                            ringColor: Theme.accent
                            onPicked: (i) => ShellSettings.baseTone = options[i].value
                        }
                    }

                    // neutral off: shell themes from matugen; show the live palette as proof (bundled fallback tones if matugen's absent, called out as such)
                    CollapsibleSection {
                        expanded: root._themeShowMatu

                        SwatchPickerRow {
                            glyph: "󰔎"; label: "Accent role"
                            options: [
                                { value: "primary",   name: "Primary"   },
                                { value: "secondary", name: "Secondary" },
                                { value: "tertiary",  name: "Tertiary"  }
                            ]
                            colors: [MatugenTheme.accent, MatugenTheme.success, MatugenTheme.warning]
                            activeIndex: options.findIndex(o => o.value === ShellSettings.matugenAccentRole)
                            tintedReadout: true
                            onPicked: (i) => ShellSettings.matugenAccentRole = options[i].value
                        }
                    }

                    SliderRow {
                        glyph: "▢"; label: "Outline strength"
                        value: ShellSettings.outlineStrength
                        min: 0.5; max: 1.6; step: 0.05
                        displayValue: Math.round(ShellSettings.outlineStrength * 100) + "%"
                        onChanged: (v) => ShellSettings.outlineStrength = v
                    }
                }
                }
            }

            Component {
                id: _secNightLight
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    visible: NightLight.toolAvailable
                    ToggleRow {
                        glyph: "󰖙"; label: "Follow sun position"
                        checked: ShellSettings.nightLightAuto
                        onToggled: ShellSettings.nightLightAuto = !ShellSettings.nightLightAuto
                    }
                    SliderRow {
                        glyph: "󰖚"; label: "Color temperature"
                        enabled: !ShellSettings.nightLightAuto
                        value: ShellSettings.nightLightTemp
                        min: 1000; max: 6500; step: 100
                        displayValue: ShellSettings.nightLightTemp + "K"
                                    + (ShellSettings.nightLightAuto ? "  ·  auto " + NightLight.locationLabel : "")
                        onChanged: (v) => { if (!ShellSettings.nightLightAuto) ShellSettings.nightLightTemp = v }
                    }
                }
                HintText {
                    visible: !NightLight.toolAvailable
                    text: "hyprsunset is not installed."
                }
                }
            }

            Component {
                id: _secSurface
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰍹"; label: "Position"
                        currentValue: ShellSettings.barPosition
                        model: [
                            { value: "top",    label: "Top"    },
                            { value: "bottom", label: "Bottom" }
                        ]
                        onChosen: (v) => ShellSettings.barPosition = v
                    }
                    ChoiceChipRow {
                        glyph: "󰲏"; label: "Height"
                        currentValue: ShellSettings.barHeight
                        model: [
                            { value: 28, label: "Compact" },
                            { value: 36, label: "Normal"  },
                            { value: 44, label: "Tall"    }
                        ]
                        onChosen: (v) => ShellSettings.barHeight = v
                    }
                    SliderRow {
                        glyph: "󰗌"; label: "Opacity"
                        value: ShellSettings.barOpacity
                        min: 0.4; max: 1.0; step: 0.02
                        displayValue: Math.round(ShellSettings.barOpacity * 100) + "%"
                        onChanged: (v) => ShellSettings.barOpacity = v
                    }
                }

                Item { width: 1; height: Theme.gapSection }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰖲"; label: "Floating bar"
                        checked: ShellSettings.barFloating
                        onToggled: ShellSettings.barFloating = !ShellSettings.barFloating
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.barFloating
                        SliderRow {
                            glyph: "󰁌"; label: "Width"
                            value: ShellSettings.barWidth
                            min: 0.5; max: 1.0; step: 0.02
                            displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
                            onChanged: (v) => ShellSettings.barWidth = v
                        }
                        ChoiceChipRow {
                            glyph: "󰀁"; label: "Shape"
                            currentValue: ShellSettings.barCornerStyle
                            model: [
                                { value: "flat",  label: "Flat"  },
                                { value: "round", label: "Round" }
                            ]
                            onChosen: (v) => ShellSettings.barCornerStyle = v
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.barCornerStyle === "round"
                            SliderRow {
                                glyph: "󱓻"; label: "Roundness"
                                value: ShellSettings.barRadius
                                min: 2; max: 28; step: 1
                                displayValue: ShellSettings.barRadius + "px"
                                onChanged: (v) => ShellSettings.barRadius = Math.round(v)
                            }
                        }
                        ToggleRow {
                            glyph: "󰘷"; label: "Shell shadows"
                            checked: ShellSettings.barShadow
                            onToggled: ShellSettings.barShadow = !ShellSettings.barShadow
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.barShadow
                            SliderRow {
                                glyph: "󰔏"; label: "Shadow depth"
                                value: ShellSettings.barShadowStrength
                                min: 0.3; max: 2.0; step: 0.1
                                displayValue: Math.round(ShellSettings.barShadowStrength * 100) + "%"
                                onChanged: (v) => ShellSettings.barShadowStrength = v
                            }
                        }
                    }
                }
                }
            }

            Component {
                id: _secSeparators
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󰡍"; label: "Compact spacing"
                        description: "Separators between groups only"
                        checked: ShellSettings.barCompact
                        onToggled: ShellSettings.barCompact = !ShellSettings.barCompact
                    }
                    ToggleRow {
                        glyph: "󰁌"; label: "Auto tighten"
                        description: "Tightens spacing when widgets crowd the bar"
                        checked: ShellSettings.barAutoCompact
                        onToggled: ShellSettings.barAutoCompact = !ShellSettings.barAutoCompact
                    }
                    SelectRow {
                        glyph: "󰻂"; label: "Separator"
                        currentValue: ShellSettings.dotStyle
                        model: [
                            { value: "·",     label: "Dot ·"     },
                            { value: "•",     label: "Bullet •"  },
                            { value: "◦",     label: "Ring ◦"    },
                            { value: "|",     label: "Pipe |"    },
                            { value: "slash", label: "Slash /"   },
                            { value: "line",  label: "Line │"    },
                            { value: "none",  label: "None"      }
                        ]
                        onChosen: (v) => ShellSettings.dotStyle = v
                    }
                    ChoiceChipRow {
                        glyph: "󰤼"; label: "Spacing"
                        currentValue: ShellSettings.barSpacing
                        model: [
                            { value: 8,  label: "Tight"  },
                            { value: 11, label: "Normal" },
                            { value: 15, label: "Loose"  }
                        ]
                        onChosen: (v) => ShellSettings.barSpacing = v
                    }
                    // no marks are drawn under "None", so the opacity control is moot
                    CollapsibleSection {
                        expanded: ShellSettings.dotStyle !== "none"
                        SliderRow {
                            glyph: ShellSettings.dotStyle === "line" ? "│"
                                 : ShellSettings.dotStyle === "slash" ? "/"
                                 : ShellSettings.dotStyle
                            glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.dotOpacity))
                            label: "Separator opacity"
                            value: ShellSettings.dotOpacity
                            min: 0.10; max: 1.0; step: 0.05
                            displayValue: Math.round(ShellSettings.dotOpacity * 100) + "%"
                            onChanged: (v) => ShellSettings.dotOpacity = v
                        }
                    }
                }
                }
            }

            Component {
                id: _secUnderline
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󰍴"; label: "Underline"
                        checked: root._underlineEnabled
                        onToggled: root._setUnderlineEnabled(!root._underlineEnabled)
                    }
                    CollapsibleSection {
                        expanded: root._underlineEnabled
                        ChoiceChipRow {
                            glyph: "󰒓"; label: "Mode"
                            currentValue: root._underlineStyle
                            model: [
                                { value: "static", label: "Line" },
                                { value: "glow",   label: "Reactive" }
                            ]
                            onChosen: (v) => root._setUnderlineStyle(v)
                        }
                        SliderRow {
                            glyph: "󰃠"
                            label: ShellSettings.underlineGlow ? "Glow strength" : "Line strength"
                            value: ShellSettings.underlineGlow ? ShellSettings.glowStrength : ShellSettings.barLineStrength
                            min: 0.5; max: 2.0; step: 0.05
                            displayValue: Math.round((ShellSettings.underlineGlow
                                ? ShellSettings.glowStrength : ShellSettings.barLineStrength) * 100) + "%"
                            onChanged: (v) => {
                                if (ShellSettings.underlineGlow) {
                                    ShellSettings.glowStrength = v
                                } else {
                                    ShellSettings.barLineStrength = v
                                }
                            }
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.underlineGlow
                            ToggleRow {
                                glyph: "󰊠"; label: "Ambient glow"
                                checked: ShellSettings.underlineIdleGlow
                                onToggled: ShellSettings.underlineIdleGlow = !ShellSettings.underlineIdleGlow
                            }
                        }
                    }
                }

                CollapsibleSection {
                    expanded: ShellSettings.underlineGlow
                    Loader {
                        width: parent.width
                        active: ShellSettings.underlineGlow || parent.height > 0.5
                        height: item ? item.implicitHeight : 0
                        sourceComponent: Component {
                            Column {
                                width: parent.width
                                SectionLabel { label: "EVENTS" }
                                SettingsCard {
                                    ToggleRow {
                                        glyph: "󰂚"; label: "Notifications"
                                        checked: ShellSettings.underlineNotifGlow
                                        onToggled: ShellSettings.underlineNotifGlow = !ShellSettings.underlineNotifGlow
                                    }
                                    ToggleRow {
                                        glyph: "󰤭"; label: "Network disconnect"
                                        checked: ShellSettings.underlineNetGlow
                                        onToggled: ShellSettings.underlineNetGlow = !ShellSettings.underlineNetGlow
                                    }
                                    ToggleRow {
                                        glyph: "󱃍"; label: "Battery low"
                                        checked: ShellSettings.underlineBattGlow
                                        onToggled: ShellSettings.underlineBattGlow = !ShellSettings.underlineBattGlow
                                    }
                                    ToggleRow {
                                        glyph: "󰔏"; label: "Temperature"
                                        checked: ShellSettings.underlineTempGlow
                                        onToggled: ShellSettings.underlineTempGlow = !ShellSettings.underlineTempGlow
                                    }
                                    ChoiceChipRow {
                                        glyph: "󰄀"; label: "Screenshots"
                                        enabled: SystemTools.hasInotifywait
                                        currentValue: root._underlineScreenshotStyle
                                        model: [
                                            { value: "off",   label: "Off" },
                                            { value: "flash", label: "Flash" },
                                            { value: "sweep", label: "Sweep" }
                                        ]
                                        onChosen: (v) => root._setUnderlineScreenshotStyle(v)
                                    }
                                    HintText {
                                        visible: !SystemTools.hasInotifywait
                                        text: "Screenshot feedback needs inotify-tools."
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }

            Component {
                id: _secClock
                SettingsClockSection {}
            }

            Component {
                id: _secWorkspaces
                SettingsWorkspacesSection {}
            }

            Component {
                id: _secMedia
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󰎇"; label: "Show artist + title"
                        checked: ShellSettings.mediaWidgetFormat === "artist-title"
                        onToggled: ShellSettings.mediaWidgetFormat = (ShellSettings.mediaWidgetFormat === "artist-title" ? "title" : "artist-title")
                    }
                    ToggleRow {
                        glyph: "󰐊"; label: "Playback helper"
                        description: "Play state and progress in the bar"
                        checked: ShellSettings.mediaWidgetHelper
                        onToggled: ShellSettings.mediaWidgetHelper = !ShellSettings.mediaWidgetHelper
                    }
                }

                Item { width: 1; height: Theme.gapSection }
                SettingsCard {
                        ToggleRow {
                            glyph: "󰱐"; label: "Audio visualizer"
                        checked: ShellSettings.mediaProgress
                        onToggled: ShellSettings.mediaProgress = !ShellSettings.mediaProgress
                        available: !SystemTools.ready || SystemTools.hasCava
                        dependsNote: SystemTools.ready ? "cava missing" : "Checking"
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.mediaProgress && SystemTools.hasCava
                        ChoiceChipRow {
                            glyph: "󰝚"; label: "Position"
                            currentValue: ShellSettings.mediaVisualizerPosition
                            model: [
                                { value: "media",  label: "Media" },
                                { value: "center", label: "Center" }
                            ]
                            onChosen: (v) => ShellSettings.mediaVisualizerPosition = v
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.mediaVisualizerPosition === "center"
                            SliderRow {
                                glyph: "󰁌"; label: "Center width"
                                value: ShellSettings.mediaVisualizerCenterWidth
                                min: 0.25; max: 1.0; step: 0.02
                                displayValue: Math.round(ShellSettings.mediaVisualizerCenterWidth * 100) + "%"
                                onChanged: (v) => ShellSettings.mediaVisualizerCenterWidth = v
                            }
                            SliderRow {
                                glyph: "󰹑"; label: "Center offset"
                                value: ShellSettings.mediaVisualizerCenterOffset
                                min: -1.0; max: 1.0; step: 0.05
                                displayValue: Math.abs(ShellSettings.mediaVisualizerCenterOffset) < 0.01
                                    ? "Center"
                                    : (ShellSettings.mediaVisualizerCenterOffset < 0 ? "Left " : "Right ")
                                        + Math.abs(Math.round(ShellSettings.mediaVisualizerCenterOffset * 100)) + "%"
                                onChanged: (v) => ShellSettings.mediaVisualizerCenterOffset = v
                            }
                        }
                        ChoiceChipRow {
                            glyph: "󰓅"; label: "Preset"
                            currentValue: ShellSettings.mediaVisualizerPreset
                            model: [
                                { value: "eco",      label: "Eco" },
                                { value: "balanced", label: "Balanced" },
                                { value: "smooth",   label: "Smooth" }
                            ]
                            onChosen: (v) => ShellSettings.mediaVisualizerPreset = v
                        }
                        ChoiceChipRow {
                            glyph: "󰝚"; label: "Shape"
                            currentValue: ShellSettings.mediaVisualizerStyle
                            model: [
                                { value: "wave",  label: "Wave" },
                                { value: "bars",  label: "Bars" },
                                { value: "pulse", label: "Pulse" }
                            ]
                            onChosen: (v) => ShellSettings.mediaVisualizerStyle = v
                        }
                        SliderRow {
                            glyph: "󰓃"; label: "Intensity"
                            value: ShellSettings.mediaVisualizerIntensity
                            min: 0.55; max: 1.65; step: 0.05
                            displayValue: Math.round(ShellSettings.mediaVisualizerIntensity * 100) + "%"
                            onChanged: (v) => ShellSettings.mediaVisualizerIntensity = v
                        }
                        ToggleRow {
                            glyph: "󰊓"; label: "Pause in fullscreen"
                            checked: ShellSettings.mediaVisualizerPauseFullscreen
                            onToggled: ShellSettings.mediaVisualizerPauseFullscreen = !ShellSettings.mediaVisualizerPauseFullscreen
                        }
                    }
                }
                }
            }

            Component {
                id: _secIndicators
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󰦩"; label: "Window title"
                        checked: ShellSettings.showWindowTitle
                        onToggled: ShellSettings.showWindowTitle = !ShellSettings.showWindowTitle
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.showWindowTitle
                        ToggleRow {
                            glyph: "󰀻"; label: "App name"
                            checked: ShellSettings.showWindowTitleApp
                            onToggled: ShellSettings.showWindowTitleApp = !ShellSettings.showWindowTitleApp
                        }
                        ToggleRow {
                            glyph: "󰉞"; label: "Center between widgets"
                            checked: ShellSettings.windowTitleCenterGap
                            onToggled: ShellSettings.windowTitleCenterGap = !ShellSettings.windowTitleCenterGap
                        }
                    }
                }

                SectionLabel { label: "INTERACTION" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰍽"; label: "Hover highlight"
                        checked: ShellSettings.barHoverHighlight
                        onToggled: ShellSettings.barHoverHighlight = !ShellSettings.barHoverHighlight
                    }
                    ToggleRow {
                        glyph: "󰈈"; label: "Reveal values on hover"
                        description: "Battery, volume, brightness, and workspace numbers"
                        checked: ShellSettings.valuesOnHover
                        onToggled: ShellSettings.valuesOnHover = !ShellSettings.valuesOnHover
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.valuesOnHover
                        ToggleRow {
                            glyph: "󰦣"; label: "Compact level bars"
                            checked: ShellSettings.hoverLevelBar
                            description: "Show battery, volume, and brightness levels before hover"
                            onToggled: ShellSettings.hoverLevelBar = !ShellSettings.hoverLevelBar
                        }
                    }
                }

                SectionLabel { label: "WIDGETS" }
                DraggableWidgetList { width: parent.width }
                Item { width: 1; height: 16 }
                }
            }

            Component {
                id: _secPopups
                SettingsPopupsSection {}
            }

            Component {
                id: _secOsd
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󱀅"; label: "Show OSD"
                        checked: ShellSettings.osdEnabled
                        onToggled: ShellSettings.osdEnabled = !ShellSettings.osdEnabled
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.osdEnabled
                        // Mode: floating pill vs bar-inline. Drives which sub-options apply.
                        ToggleRow {
                            glyph: "󰀱"; label: "Show in bar"; badge: "beta"
                            description: "Volume and brightness in the bar center"
                            checked: ShellSettings.osdBarIntegrated
                            onToggled: ShellSettings.osdBarIntegrated = !ShellSettings.osdBarIntegrated
                        }
                        ToggleRow {
                            glyph: "󰖲"; label: "Match bar shape"
                            enabled: !ShellSettings.osdBarIntegrated
                            checked: ShellSettings.osdMatchBar
                            onToggled: ShellSettings.osdMatchBar = !ShellSettings.osdMatchBar
                            dependsNote: ShellSettings.osdBarIntegrated ? "Pill only" : ""
                        }
                        ChoiceChipRow {
                            glyph: "󰔛"; label: "Dismiss after"
                            currentValue: ShellSettings.osdTimeout
                            model: [
                                { value: 1000, label: "1s" },
                                { value: 2000, label: "2s" },
                                { value: 3000, label: "3s" },
                                { value: 5000, label: "5s" }
                            ]
                            onChosen: (v) => ShellSettings.osdTimeout = v
                        }
                        ChoiceChipRow {
                            glyph: "󰒓"; label: "Show for"
                            currentValue: ShellSettings.osdKindFilter
                            model: [
                                { value: "both",       glyph: "󰓎", label: "Both" },
                                { value: "volume",     glyph: "󰕾", label: "Vol"  },
                                { value: "brightness", glyph: "󰃟", label: "Brt"  }
                            ]
                            onChosen: (v) => ShellSettings.osdKindFilter = v
                        }
                        ToggleRow {
                            glyph: "󰓎"; label: "Volume emphasis"
                            description: "Warm tint as volume nears max"
                            checked: ShellSettings.osdVolumeTint
                            onToggled: ShellSettings.osdVolumeTint = !ShellSettings.osdVolumeTint
                        }
                    }
                }
                }
            }

            Component {
                id: _secWarnings
                Column {
                width: _detailBody.width
                spacing: 0

                SectionLabel { label: "BATTERY"; first: true; visible: Battery.available }
                SettingsCard {
                    visible: Battery.available
                    ChoiceChipRow {
                        glyph: "󱟢"; label: "Low battery alert"
                        currentValue: root._battAlertMode
                        model: root._alertChipModel
                        onChosen: (v) => root._setBattAlert(v)
                    }
                    CollapsibleSection {
                        expanded: root._battAlertMode !== "off"
                        SliderRow {
                            glyph: "󱟢"; label: "Alert below"
                            value: ShellSettings.batteryLowThreshold
                            min: 5; max: 50; step: 5
                            displayValue: ShellSettings.batteryLowThreshold + "%"
                            onChanged: (v) => ShellSettings.batteryLowThreshold = v
                            glyphColor: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
                        }
                        HintText { text: "Escalates to critical at " + Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2)) + "%." }
                    }
                    ToggleRow {
                        glyph: "󰂄"; label: "Fully-charged alert"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdChargedNotify
                        onToggled: ShellSettings.osdChargedNotify = !ShellSettings.osdChargedNotify
                        dependsNote: "OSD off"
                    }
                }

                SectionLabel { label: "CPU TEMPERATURE"; first: !Battery.available }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰔏"; label: "High temp alert"
                        currentValue: root._tempAlertMode
                        model: root._alertChipModel
                        onChosen: (v) => root._setTempAlert(v)
                    }
                    CollapsibleSection {
                        expanded: root._tempAlertMode !== "off"
                        SliderRow {
                            glyph: "󰔏"; label: "Alert above"
                            value: ShellSettings.tempHotThreshold
                            min: 70; max: 105; step: 5
                            displayValue: ShellSettings.tempHotThreshold + "°"
                            onChanged: (v) => ShellSettings.tempHotThreshold = v
                            glyphColor: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
                        }
                        HintText { text: "Escalates to critical at " + (ShellSettings.tempHotThreshold + 8) + "°." }
                    }
                }

                CollapsibleSection {
                    expanded: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn
                    Loader {
                        width: parent.width
                        active: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn || parent.height > 0.5
                        height: item ? item.implicitHeight : 0
                        sourceComponent: Component {
                            Column {
                                width: parent.width
                                SectionLabel { label: "ALERTS" }
                                SettingsCard {
                                    ChoiceChipRow {
                                        glyph: "󰀦"; label: "Auto-dismiss"
                                        currentValue: ShellSettings.sysAlertTimeout
                                        model: [
                                            { value: 5000,  label: "5s"   },
                                            { value: 10000, label: "10s"  },
                                            { value: 20000, label: "20s"  },
                                            { value: 0,     label: "Stay" }
                                        ]
                                        onChosen: (v) => ShellSettings.sysAlertTimeout = v
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }

            Component {
                id: _secSystem
                Column {
                width: _detailBody.width
                spacing: 0

                SectionLabel { label: "HARDWARE"; first: true; visible: Brightness.devices.length > 1 }
                SettingsCard {
                    visible: Brightness.devices.length > 1
                    SelectRow {
                        glyph: "󰃟"; label: "Brightness display"
                        currentValue: Brightness.deviceChoice
                        model: Brightness.deviceChoices
                        onChosen: (v) => ShellSettings.brightnessDevice = v
                    }
                }

                SectionLabel { label: "ACCESSIBILITY"; first: Brightness.devices.length <= 1 }
                SettingsCard {
                    SelectRow {
                        glyph: "󰛖"; label: "Font"
                        currentValue: ShellSettings.fontFamily
                        model: {
                            const m = [{ value: "", label: "JetBrainsMono (default)", fontFamily: "JetBrainsMono Nerd Font" }]
                            const fams = FontScan.families
                            for (let i = 0; i < fams.length; i++) {
                                const f = fams[i]
                                if (f === "JetBrainsMono Nerd Font") continue
                                m.push({ value: f, label: f.replace(/ Nerd Font( Mono)?$/, ""), fontFamily: f })
                            }
                            const cur = ShellSettings.fontFamily
                            if (cur.length > 0 && m.findIndex(e => e.value === cur) < 0)
                                m.push({ value: cur, label: cur.replace(/ Nerd Font( Mono)?$/, "") + " (not installed)" })
                            return m
                        }
                        onChosen: (v) => ShellSettings.fontFamily = v
                    }
                    SelectRow {
                        glyph: "󰍉"; label: "UI scale"
                        currentValue: ShellSettings.uiScale
                        model: [
                            { value: 0.8,  label: "80%"  },
                            { value: 0.9,  label: "90%"  },
                            { value: 1.0,  label: "100%" },
                            { value: 1.1,  label: "110%" },
                            { value: 1.15, label: "115%" }
                        ]
                        onChosen: (v) => ShellSettings.uiScale = v
                    }
                    ToggleRow {
                        glyph: "󰹑"; label: "High contrast"
                        checked: ShellSettings.highContrast
                        onToggled: ShellSettings.highContrast = !ShellSettings.highContrast
                    }
                    ToggleRow {
                        glyph: "󱖳"; label: "Reduce motion"
                        checked: ShellSettings.reduceMotion
                        onToggled: ShellSettings.reduceMotion = !ShellSettings.reduceMotion
                    }
                }

                Loader {
                    width: parent.width
                    active: Quickshell.screens.length > 1
                    height: item ? item.implicitHeight : 0
                    sourceComponent: Component {
                        Column {
                            width: parent.width
                            SectionLabel { label: "MONITORS" }
                            SettingsCard {
                                ChoiceChipRow {
                                    glyph: "󰍹"; label: "Popups & OSD on"
                                    currentValue: ShellSettings.overlayMonitor
                                    model: {
                                        const t = [{ value: "", label: "Focus" }]
                                        const s = Quickshell.screens || []
                                        for (let i = 0; i < s.length; i++) {
                                            const name = s[i].name
                                            t.push({ value: name, label: name.length > 12 ? name.slice(0, 9) + "..." : name })
                                        }
                                        return t
                                    }
                                    onChosen: (v) => ShellSettings.overlayMonitor = v
                                }
                                Repeater {
                                    model: Quickshell.screens
                                    delegate: ToggleRow {
                                        required property var modelData
                                        glyph: "󰍺"
                                        label: "Bar on " + modelData.name
                                        checked: Monitors.barEnabled(modelData)
                                        onToggled: Monitors.setBarEnabled(modelData.name, !checked)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: Theme.gapSection }
                SettingsCard {
                    Item {
                        id: _resetRow
                        width: parent.width; height: 44
                        property bool armed: false
                        property real topRadius:    0
                        property real bottomRadius: 0

                        function _activate(): void {
                            if (armed) { armed = false; ShellSettings.resetToDefaults() }
                            else armed = true
                        }

                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Reset all settings"
                        Accessible.description: armed ? "Activate again to confirm" : ""
                        onActiveFocusChanged: if (!activeFocus) armed = false
                        Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
                        Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
                        Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }

                        HoverHandler {
                            id: _resetHover
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: if (!hovered) _resetRow.armed = false
                        }
                        TapHandler { onTapped: _resetRow._activate() }
                        RowHoverBg {
                            anchors.fill: parent
                            topRadius:    _resetRow.topRadius
                            bottomRadius: _resetRow.bottomRadius
                            active: _resetHover.hovered || _resetRow.armed || _resetRow.activeFocus
                            focusActive: _resetRow.activeFocus
                            focusColor: _resetRow.armed ? Theme.error : Theme.accent
                            fillColor: _resetRow.armed ? Theme.error : Theme.subtext
                            fillOpacity: _resetRow.armed ? 0.10 : _resetRow.activeFocus ? 0.13 : 0.08
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: "󰦛"
                                color: _resetRow.armed ? Theme.error : Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.iconSize + 2
                                renderType: Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Reset all settings"
                                color: _resetRow.armed ? Theme.error : Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: _resetRow.armed ? "activate to confirm" : ""
                            color: Theme.withAlpha(Theme.error, 0.7)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                }
                }
            }

            Component {
                id: _secUpdates
                SettingsUpdatesSection {}
            }
            }   // _detailBody
    }
}
