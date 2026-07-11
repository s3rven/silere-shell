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
                    m[c.section] = { glyph: c.glyph, label: c.label, group: it.label }
                }
            } else {
                m[it.section] = { glyph: it.glyph, label: it.label, group: "" }
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
                                            ?? ({ glyph: "", label: "", group: "" })

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

                            readonly property var _accents: [
                                { color: "#b8bdd8", name: "Mist"   },
                                { color: "#82aee5", name: "Blue"   },
                                { color: "#b79bd7", name: "Violet" },
                                { color: "#78bfb5", name: "Teal"   },
                                { color: "#94bd8b", name: "Green"  },
                                { color: "#dd92a2", name: "Rose"   },
                                { color: "#d4ad77", name: "Amber"  }
                            ]

                            property string _hoverName: ""
                            readonly property string _activeName: {
                                if (ShellSettings.neutralAccentAuto) return "Auto"
                                for (let i = 0; i < _accents.length; i++)
                                    if (_accents[i].color === ShellSettings.neutralAccent) return _accents[i].name
                                return "Custom"
                            }
                            readonly property string _shownName: _hoverName.length > 0 ? _hoverName : _activeName

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
                                color:          Theme.withAlpha(Theme.subtext, 0.7)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType:     Text.NativeRendering
                                elide:          Text.ElideRight
                            }

                            Row {
                                id: _swatchRow
                                anchors.top:        parent.top
                                anchors.topMargin:  32
                                anchors.left:       parent.left;  anchors.leftMargin:  12
                                anchors.right:      parent.right; anchors.rightMargin: 12
                                height: 32
                                spacing: Math.max(4, (width - 8 * 26) / 7)

                                AccentSwatch {
                                    chipColor: MatugenTheme.accent
                                    name:      "Auto"
                                    active:    ShellSettings.neutralAccentAuto
                                    onPicked:  ShellSettings.neutralAccentAuto = true
                                    onHoverChanged: (n, h) => _accentPicker._hoverName =
                                        h ? n : (_accentPicker._hoverName === n ? "" : _accentPicker._hoverName)

                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2; spacing: 2
                                        Repeater {
                                            model: 4
                                            Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(0,0,0,0.35) }
                                        }
                                    }
                                }

                                Repeater {
                                    model: _accentPicker._accents
                                    delegate: AccentSwatch {
                                        id: _sw
                                        required property var modelData
                                        chipColor: modelData.color
                                        name:      modelData.name
                                        active:    !ShellSettings.neutralAccentAuto && ShellSettings.neutralAccent === modelData.color
                                        onPicked:  { ShellSettings.neutralAccentAuto = false; ShellSettings.neutralAccent = modelData.color }
                                        onHoverChanged: (n, h) => _accentPicker._hoverName =
                                            h ? n : (_accentPicker._hoverName === n ? "" : _accentPicker._hoverName)

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8; height: 8; radius: 4
                                            antialiasing: true
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            opacity: _sw.active ? 1 : 0
                                            scale:   _sw.active ? 1 : 0.3
                                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(125); easing.type: Easing.OutCubic } }
                                        }
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

                        ChoiceChipRow {
                            glyph: "󰏘"; label: "Base tone"
                            currentValue: ShellSettings.baseTone
                            model: [
                                { value: "charcoal", label: "Charcoal", color: "#191b21" },
                                { value: "black",    label: "Black",    color: "#111216" }
                            ]
                            onChosen: (v) => ShellSettings.baseTone = v
                        }
                    }

                    // neutral off: shell themes from matugen; show the live palette as proof (bundled fallback tones if matugen's absent, called out as such)
                    CollapsibleSection {
                        expanded: root._themeShowMatu

                        Item {
                            id: _matuAccentRow
                            width: parent.width
                            height: 44

                            readonly property var _roles: [
                                { key: "primary",   c: MatugenTheme.accent,  n: "Primary"   },
                                { key: "secondary", c: MatugenTheme.success, n: "Secondary" },
                                { key: "tertiary",  c: MatugenTheme.warning, n: "Tertiary"  }
                            ]
                            property real topRadius: 0
                            property real bottomRadius: 0
                            property real cardInset: 1

                            HoverHandler { id: _matuHover; enabled: _matuAccentRow.enabled }
                            RowHoverBg {
                                anchors.fill: parent
                                topRadius: _matuAccentRow.topRadius
                                bottomRadius: _matuAccentRow.bottomRadius
                                cardInset: _matuAccentRow.cardInset
                                active: _matuHover.hovered && _matuAccentRow.enabled
                                fillOpacity: 0.08
                            }

                            Text {
                                id: _matuGlyph
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: "󰔎"
                                color: Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font
                                font.pixelSize: Settings.iconSize + 2
                                renderType: Text.NativeRendering
                            }

                            Text {
                                anchors.left: _matuGlyph.right
                                anchors.leftMargin: 10
                                anchors.right: _matuSwatches.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Accent role"
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }

                            Row {
                                id: _matuSwatches
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                spacing: 8

                                Repeater {
                                    model: _matuAccentRow._roles
                                    delegate: AccentSwatch {
                                        id: _mrSw
                                        required property var modelData
                                        chipColor: modelData.c
                                        name: modelData.n
                                        active: ShellSettings.matugenAccentRole === modelData.key
                                        onPicked: ShellSettings.matugenAccentRole = modelData.key

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8; height: 8; radius: 4
                                            antialiasing: true
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            opacity: _mrSw.active ? 1 : 0
                                            scale: _mrSw.active ? 1 : 0.3
                                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(125); easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
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
                                    // idle-breath ceiling follows the main strength so low settings stay calm
                                    ShellSettings.activeGlowStrength = Math.min(1, 0.45 + 0.4 * v)
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
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰃭"; label: "Date"
                        currentValue: !ShellSettings.clockShowDate ? "off"
                                      : ShellSettings.compactDate ? "compact" : "normal"
                        model: [
                            { value: "off",     label: "Off"     },
                            { value: "normal",  label: "Normal"  },
                            { value: "compact", label: "Compact" }
                        ]
                        onChosen: (v) => {
                            ShellSettings.clockShowDate = v !== "off"
                            ShellSettings.compactDate   = v === "compact"
                        }
                    }
                    ChoiceChipRow {
                        glyph: "󰔟"; label: "Time"
                        currentValue: ShellSettings.clock12h ? "12h" : "24h"
                        model: [
                            { value: "24h", label: "24h" },
                            { value: "12h", label: "12h" }
                        ]
                        onChosen: (v) => ShellSettings.clock12h = v === "12h"
                    }
                    ToggleRow {
                        glyph: "󱑂"; label: "Seconds"
                        checked: ShellSettings.showSeconds
                        onToggled: ShellSettings.showSeconds = !ShellSettings.showSeconds
                    }
                }
                }
            }

            Component {
                id: _secWorkspaces
                Column {
                width: _detailBody.width
                spacing: 0

                SectionLabel { label: "LAYOUT" }
                SettingsCard {
                    SliderRow {
                        glyph: "󰕰"; label: "Visible"
                        value: ShellSettings.wsMinVisible
                        min: 1; max: 10; step: 1
                        displayValue: ShellSettings.wsMinVisible
                        onChanged: (v) => ShellSettings.wsMinVisible = v
                    }
                    ToggleRow {
                        glyph: "󰗘"; label: "Animated switch"
                        checked: ShellSettings.workspaceShift
                        onToggled: ShellSettings.workspaceShift = !ShellSettings.workspaceShift
                    }
                    ToggleRow {
                        glyph: "󱕒"; label: "Scroll to switch"
                        checked: ShellSettings.wsScrollSwitch
                        onToggled: ShellSettings.wsScrollSwitch = !ShellSettings.wsScrollSwitch
                    }
                    ToggleRow {
                        glyph: "󰂟"; label: "Notification pulse"
                        checked: ShellSettings.wsNotifPulse
                        onToggled: ShellSettings.wsNotifPulse = !ShellSettings.wsNotifPulse
                    }
                }

                SectionLabel { label: "CONTENT" }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "◆"; label: "Active marker"
                        currentValue: ShellSettings.wsActiveMarker
                        model: [
                            { value: "gem", label: "Gem" },
                            { value: "dot", label: "Dot" }
                        ]
                        onChosen: (v) => ShellSettings.wsActiveMarker = v
                    }
                    ToggleRow {
                        glyph: "󰎠"; label: "Numbers"
                        checked: ShellSettings.wsShowNumbers
                        onToggled: ShellSettings.wsShowNumbers = !ShellSettings.wsShowNumbers
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.wsShowNumbers
                        ToggleRow {
                            glyph: "󰮚"; label: "Roman numerals"
                            checked: ShellSettings.wsRomanNumerals
                            onToggled: ShellSettings.wsRomanNumerals = !ShellSettings.wsRomanNumerals
                        }
                    }
                    SliderRow {
                        glyph: ShellSettings.wsShowNumbers
                            ? (ShellSettings.wsRomanNumerals ? "Ⅰ" : "1")
                            : "•"
                        glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.wsMarkerOpacity))
                        label: "Marker opacity"
                        value: ShellSettings.wsMarkerOpacity
                        min: 0.2; max: 1.0; step: 0.05
                        displayValue: Math.round(ShellSettings.wsMarkerOpacity * 100) + "%"
                        onChanged: (v) => ShellSettings.wsMarkerOpacity = v
                    }
                    ToggleRow {
                        glyph: "󰀻"; label: "App icons"; badge: "beta"
                        description: "Show up to three running apps on occupied workspaces"
                        checked: ShellSettings.wsShowAppIcons
                        onToggled: ShellSettings.wsShowAppIcons = !ShellSettings.wsShowAppIcons
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.wsShowAppIcons
                        SliderRow {
                            glyph: "󰋩"; label: "Icon opacity"
                            value: ShellSettings.wsIconOpacity
                            min: 0.3; max: 1.0; step: 0.05
                            displayValue: Math.round(ShellSettings.wsIconOpacity * 100) + "%"
                            onChanged: (v) => ShellSettings.wsIconOpacity = v
                        }
                    }
                }
                }
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
                        glyph: "󰈈"; label: "Show values on hover"
                        checked: ShellSettings.valuesOnHover
                        onToggled: ShellSettings.valuesOnHover = !ShellSettings.valuesOnHover
                    }
                }

                SectionLabel { label: "WIDGETS" }
                DraggableWidgetList { width: parent.width }
                Item { width: 1; height: 16 }
                }
            }

            Component {
                id: _secPopups
                Column {
                width: _detailBody.width
                spacing: 0

                SettingsCard {
                    ToggleRow {
                        glyph: "󰂚"; label: "Popup notifications"
                        checked: ShellSettings.notifPopupEnabled
                        onToggled: ShellSettings.notifPopupEnabled = !ShellSettings.notifPopupEnabled
                    }
                    ToggleRow {
                        glyph: "󰊓"; label: "Hide in fullscreen"
                        enabled: ShellSettings.notifPopupEnabled
                        checked: ShellSettings.notifFullscreenSilence
                        onToggled: ShellSettings.notifFullscreenSilence = !ShellSettings.notifFullscreenSilence
                    }
                }

                SectionLabel { label: "DISPLAY" }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰔛"; label: "Dismiss after"
                        enabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifDefaultTimeout
                        model: [
                            { value: 3000,  label: "3s"  },
                            { value: 5000,  label: "5s"  },
                            { value: 10000, label: "10s" },
                            { value: 15000, label: "15s" }
                        ]
                        onChosen: (v) => ShellSettings.notifDefaultTimeout = v
                    }
                    ChoiceChipRow {
                        glyph: "󰍹"; label: "Position"
                        enabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifPosition
                        model: [
                            { value: "top-left",   label: "Left"   },
                            { value: "top-center", label: "Center" },
                            { value: "top-right",  label: "Right"  }
                        ]
                        onChosen: (v) => ShellSettings.notifPosition = v
                    }
                    ChoiceChipRow {
                        glyph: "󰽘"; label: "Max shown"
                        enabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifMaxVisible
                        model: [
                            { value: 3, label: "3"   },
                            { value: 5, label: "5"   },
                            { value: 0, label: "All" }
                        ]
                        onChosen: (v) => ShellSettings.notifMaxVisible = v
                    }
                }

                SectionLabel { label: "QUIET HOURS" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰂛"; label: "Auto do not disturb"
                        checked: ShellSettings.dndSchedule
                        onToggled: ShellSettings.dndSchedule = !ShellSettings.dndSchedule
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.dndSchedule
                        SliderRow {
                            glyph: "󰃰"; label: "From"
                            displayValue: (ShellSettings.dndFrom < 10 ? "0" : "") + ShellSettings.dndFrom + ":00"
                            value: ShellSettings.dndFrom
                            min: 0; max: 23; step: 1
                            onChanged: (v) => ShellSettings.dndFrom = v
                        }
                        SliderRow {
                            glyph: "󰃰"; label: "To"
                            displayValue: (ShellSettings.dndTo < 10 ? "0" : "") + ShellSettings.dndTo + ":00"
                            value: ShellSettings.dndTo
                            min: 0; max: 23; step: 1
                            onChanged: (v) => ShellSettings.dndTo = v
                        }
                    }
                }
                }
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
                    // Mode: floating pill vs bar-inline. Drives which sub-options apply.
                    ToggleRow {
                        glyph: "󰀱"; label: "Show in bar"; badge: "beta"
                        description: "Volume and brightness in the bar center"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdBarIntegrated
                        onToggled: ShellSettings.osdBarIntegrated = !ShellSettings.osdBarIntegrated
                    }
                    ToggleRow {
                        glyph: "󰖲"; label: "Match bar shape"
                        enabled: ShellSettings.osdEnabled && !ShellSettings.osdBarIntegrated
                        checked: ShellSettings.osdMatchBar
                        onToggled: ShellSettings.osdMatchBar = !ShellSettings.osdMatchBar
                        dependsNote: ShellSettings.osdEnabled ? "Pill only" : ""
                    }
                    ChoiceChipRow {
                        glyph: "󰔛"; label: "Dismiss after"
                        enabled: ShellSettings.osdEnabled
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
                        enabled: ShellSettings.osdEnabled
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
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdVolumeTint
                        onToggled: ShellSettings.osdVolumeTint = !ShellSettings.osdVolumeTint
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

                Item { width: 1; height: 16 }
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
                Column {
                            width: _detailBody.width

                            SettingsCard {
                                UpdateStatusCard {
                                    flat: true
                                    glyph: ShellUpdate.checking || ShellUpdate.applying ? "󰓦"
                                        : ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0 ? "󰀦"
                                        : ShellUpdate.pending ? "󰚰" : "󰄬"
                                    title: "Silere Shell"
                                    status: ShellUpdate.statusText
                                    meta: ShellUpdate.currentVersion.length > 0 ? "#" + ShellUpdate.currentVersion : ""
                                    detail: ShellUpdate.lastApplyError.length > 0 ? ShellUpdate.lastApplyError
                                        : ShellUpdate.lastCheckError.length > 0 ? ShellUpdate.lastCheckError
                                        : ShellUpdate.pending ? ShellUpdate.summary : ""
                                    detailError: ShellUpdate.lastApplyError.length > 0 || ShellUpdate.lastCheckError.length > 0
                                    statusColor: ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0
                                        ? Theme.warning : ShellUpdate.checking || ShellUpdate.applying || ShellUpdate.pending
                                            ? Theme.accent : Theme.success
                                    busy: ShellUpdate.checking || ShellUpdate.applying

                                    primaryLabel: ShellUpdate.pending || ShellUpdate.applying ? "Install" : "Check"
                                    primaryGlyph: ShellUpdate.pending ? "󰅢" : "󰓦"
                                    primaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
                                    primaryEmphasis: ShellUpdate.pending
                                    onPrimaryTriggered: {
                                        if (ShellUpdate.pending) ShellUpdate.apply()
                                        else ShellUpdate.check()
                                    }

                                    secondaryShown: ShellUpdate.pending && !ShellUpdate.applying
                                    secondaryGlyph: "󰑐"
                                    secondaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
                                    onSecondaryTriggered: ShellUpdate.check()
                                }

                                UpdateStatusCard {
                                    flat: true
                                    glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
                                    title: "System packages"
                                    status: Updates.statusText
                                    meta: Updates.managerLabel
                                    detail: Updates.lastFailed ? Updates.lastError : ""
                                    detailError: Updates.lastFailed
                                    statusColor: Updates.lastFailed ? Theme.warning
                                        : Updates.isChecking ? Theme.accent
                                        : Updates.ready && Updates.count === 0 ? Theme.success
                                        : Updates.count > 0 ? Theme.accent : Theme.subtext
                                    busy: Updates.isChecking

                                    primaryLabel: !SystemTools.ready ? "Detecting…"
                                        : !Updates.supported ? "Unavailable"
                                        : !ShellSettings.updatesWidget ? "Off"
                                        : Updates.isChecking ? "Checking…" : "Check"
                                    primaryGlyph: "󰓦"
                                    primaryEnabled: SystemTools.ready && Updates.supported && ShellSettings.updatesWidget && !Updates.isChecking
                                    onPrimaryTriggered: Updates.refresh()
                                }
                                ToggleRow {
                                    glyph: "󰚰"; label: "Track package updates"
                                    description: "Pending-update badge in the bar"
                                    checked: ShellSettings.updatesWidget
                                    onToggled: ShellSettings.updatesWidget = !ShellSettings.updatesWidget
                                    available: !SystemTools.ready || Updates.supported
                                    dependsNote: "No package manager"
                                }
                                ToggleRow {
                                    glyph: "󰥔"; label: "Daily update check"
                                    checked: ShellUpdate.timerEnabled
                                    enabled: !ShellUpdate.timerBusy
                                    available: ShellUpdate.timerSupported
                                    dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
                                    onToggled: ShellUpdate.setTimerEnabled(!ShellUpdate.timerEnabled)
                                }
                                HintText { text: "Checks never install anything on their own." }
                            }
                        }
            }
            }   // _detailBody
    }
}
