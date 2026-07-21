pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

PageShell {
    id: root

    implicitHeight: _detail.height
    enterFade: 145; exitFade: 110

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
        widgets: _secWidgets,
        popups: _secPopups, osd: _secOsd, warnings: _secWarnings,
        updates: _secUpdates, system: _secSystem
    })

    // section id → { glyph, label, group, description, index }, for the detail-pane header
    readonly property var _sectionMeta: {
        const m = ({})
        const tree = MenuState.settingsTree
        let index = 0
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
            if (it.children) {
                for (let j = 0; j < it.children.length; j++) {
                    const c = it.children[j]
                    m[c.section] = {
                        glyph: c.glyph,
                        label: c.label,
                        group: it.label,
                        description: c.description ?? "",
                        index: index++
                    }
                }
            } else {
                m[it.section] = {
                    glyph: it.glyph,
                    label: it.label,
                    group: "Settings",
                    description: it.description ?? "",
                    index: index++
                }
            }
        }
        return m
    }

    function _alertMode(osdEnabled, glowEnabled): string {
        const o = osdEnabled === true
        const g = glowEnabled === true && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setAlertMode(v, osdKey, glowKey): void {
        ShellSettings[osdKey] = (v === "osd" || v === "both")
        ShellSettings[glowKey] = (v === "glow" || v === "both")
    }
    readonly property string _battAlertMode: root._alertMode(
        ShellSettings.osdBatteryWarn, ShellSettings.underlineBattGlow)
    readonly property string _tempAlertMode: root._alertMode(
        ShellSettings.osdTempWarn, ShellSettings.underlineTempGlow)

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

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (ShellSettings.reduceMotion) {
                    root._shownSection = MenuState.settingsSection
                    _detail.opacity = 1
                    return
                }
                if (!_detailSwap.running) _detailSwap.restart()
            }
        }

        SequentialAnimation {
            id: _detailSwap
            NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.ms(55); easing.type: Easing.InCubic }
            ScriptAction    { script: root._shownSection = MenuState.settingsSection }
            NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.ms(105); easing.type: Easing.OutCubic }
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
            height: 58
            readonly property var _meta: root._sectionMeta[root._shownSection]
                ?? ({ glyph: "", label: "", group: "Settings", description: "", index: 0 })

            Text {
                id: _hdrPath
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 1
                text: _detailHeader._meta.group
                color: Theme.withAlpha(Theme.accent, 0.76)
                font.family: Settings.font
                font.pixelSize: Math.max(8, Settings.fontSize - 3)
                font.letterSpacing: 0.55
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Item {
                id: _hdrIconSlot
                anchors.left: parent.left
                anchors.top: _hdrPath.bottom
                anchors.topMargin: 6
                width: 22
                height: 34

                Text {
                    anchors.centerIn: parent
                    text: _detailHeader._meta.glyph
                    color: Theme.withAlpha(Theme.accent, 0.82)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize + 2
                    renderType: Text.NativeRendering
                }
            }
            Text {
                id: _hdrTitle
                anchors.left: _hdrIconSlot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.top: _hdrIconSlot.top
                anchors.topMargin: -1
                text: _detailHeader._meta.label
                color: Theme.text
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 3
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Text {
                anchors.left: _hdrTitle.left
                anchors.right: parent.right
                anchors.top: _hdrTitle.bottom
                anchors.topMargin: 2
                text: _detailHeader._meta.description
                color: Theme.withAlpha(Theme.subtext, 0.58)
                font.family: Settings.font
                font.pixelSize: Math.max(8, Settings.fontSize - 2)
                renderType: Text.NativeRendering
                elide: Text.ElideRight
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

                SectionLabel { glyph: "󰉦"; label: "THEME MODE"; first: true }
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
                }

                SectionLabel { glyph: "󰏘"; label: "PALETTE" }
                SettingsCard {
                CollapsibleSection {
                    expanded: ShellSettings.neutralTheme

                    Item {
                        id: _accentPicker
                        width: parent.width
                        height: 104

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
                            anchors.left:           parent.left; anchors.leftMargin: 16
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
                            width:                  Math.min(176, Math.max(56, parent.width * 0.42))
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

                        Flickable {
                            id: _swatchViewport
                            anchors.top:        parent.top
                            anchors.topMargin:  32
                            anchors.left:       parent.left;  anchors.leftMargin:  12
                            anchors.right:      parent.right; anchors.rightMargin: 12
                            height: 32
                            contentWidth: _swatchRow.width
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsMovement: Flickable.StopAtBounds
                            interactive: contentWidth > width + 1
                            clip: true

                            function revealIndex(index: int): void {
                                if (!interactive || index < 0) return
                                const left = _swatchRow.itemLeft(index) - _swatchRow.edgePadding
                                const right = _swatchRow.itemRight(index) + _swatchRow.edgePadding
                                if (left < contentX) contentX = left
                                else if (right > contentX + width) contentX = right - width
                            }

                            SwatchRow {
                                id: _swatchRow
                                width: Math.max(_swatchViewport.width, implicitWidth)
                                height: parent.height
                                spread: true
                                options: _accentPicker._options
                                colors:  _accentPicker._swColors
                                activeIndex: _accentPicker._activeIndex
                                onActiveIndexChanged: Qt.callLater(function() {
                                    _swatchViewport.revealIndex(_swatchRow.activeIndex)
                                })
                                onPicked: (i) => {
                                    if (_accentPicker._options[i].auto) {
                                        ShellSettings.neutralAccentAuto = true
                                    } else {
                                        ShellSettings.neutralAccentAuto = false
                                        ShellSettings.neutralAccent = _accentPicker._options[i].color
                                    }
                                }
                            }
                        }

                        HueStrip {
                            id: _hueStrip
                            anchors.top:       _swatchViewport.bottom; anchors.topMargin: 6
                            anchors.left:      parent.left;  anchors.leftMargin:  12
                            anchors.right:     parent.right; anchors.rightMargin: 12
                            height: 24
                            hue: _accentPicker._curHue
                            saturation: 0.72
                            lightness: _accentPicker._accentL
                            thumbColor: _accentPicker._curColor
                            dimmed: ShellSettings.neutralAccentAuto
                            accessibleName: "Accent hue"
                            accessibleDescription: ShellSettings.neutralAccentAuto
                                ? "Auto accent; adjust to switch to a custom color"
                                : _accentPicker._shownName
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
                    expanded: !ShellSettings.neutralTheme

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
                    glyph: "󰃇"; label: "Outline strength"
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
            SettingsNightLightSection {}
        }

        Component {
            id: _secSurface
            SettingsSurfaceSection {}
        }

        Component {
            id: _secSeparators
            SettingsSeparatorsSection {}
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
                id: _glowSection
                expanded: ShellSettings.underlineGlow
                Loader {
                    width: parent.width
                    active: ShellSettings.underlineGlow || _glowSection.height > 0.5
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
            SettingsMediaSection {}
        }

        Component {
            id: _secIndicators
            SettingsIndicatorsSection {}
        }

        Component {
            id: _secWidgets
            Column {
            width: _detailBody.width
            spacing: 0

            DraggableWidgetList { width: parent.width }
            }
        }

        Component {
            id: _secPopups
            SettingsPopupsSection {}
        }

        Component {
            id: _secOsd
            SettingsOsdSection {}
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
                    onChosen: (v) => root._setAlertMode(v, "osdBatteryWarn", "underlineBattGlow")
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
                    onChosen: (v) => root._setAlertMode(v, "osdTempWarn", "underlineTempGlow")
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
                id: _alertsSection
                expanded: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn
                Loader {
                    width: parent.width
                    active: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn || _alertsSection.height > 0.5
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
            SettingsSystemSection {}
        }

        Component {
            id: _secUpdates
            SettingsUpdatesSection {
                animationActive: root.active && root._shownSection === "updates"
                    && !root.powerOpen && !Idle.isIdle
            }
        }
        }   // _detailBody
    }
}
