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

    // Lags behind MenuState.settingsSection during the swap animation; the
    // detail pane renders whichever section this points at.
    property string _shownSection: MenuState.settingsSection

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

    readonly property string _underlineBrightness: {
        const v = ShellSettings.underlineGlow
            ? ShellSettings.glowStrength : ShellSettings.barLineStrength
        return v < 0.9 ? "soft" : v > 1.2 ? "bright" : "normal"
    }

    function _setUnderlineBrightness(level) {
        const n = level === "soft" ? 0.7 : level === "bright" ? 1.4 : 1.0
        if (ShellSettings.underlineGlow) {
            ShellSettings.glowStrength = n
            ShellSettings.activeGlowStrength = level === "soft" ? 0.65 : level === "bright" ? 1.0 : 0.85
        } else {
            ShellSettings.barLineStrength = n
        }
    }

    // ── Detail pane ────────────────────────────────────────────────────────
    Item {
        id: _detail
        width:  root.width
        height: _detailHeader.height + _bodyGap + _detailBody.height

        readonly property int _bodyGap: 8

        readonly property real _bodyH:
                root._shownSection === "theme"      ? _secTheme.implicitHeight
              : root._shownSection === "motion"     ? _secMotion.implicitHeight
              : root._shownSection === "nightlight" ? _secNightLight.implicitHeight
              : root._shownSection === "surface"    ? _secSurface.implicitHeight
              : root._shownSection === "separators" ? _secSeparators.implicitHeight
              : root._shownSection === "underline"  ? _secUnderline.implicitHeight
              : root._shownSection === "clock"      ? _secClock.implicitHeight
              : root._shownSection === "workspaces" ? _secWorkspaces.implicitHeight
              : root._shownSection === "media"      ? _secMedia.implicitHeight
              : root._shownSection === "indicators" ? _secIndicators.implicitHeight
              : root._shownSection === "popups"     ? _secPopups.implicitHeight
              : root._shownSection === "osd"        ? _secOsd.implicitHeight
              : root._shownSection === "warnings"   ? _secWarnings.implicitHeight
              : root._shownSection === "updates"    ? _secUpdates.implicitHeight
              :                                       _secSystem.implicitHeight

        property real _slide: 0
        transform: Translate { y: _detail._slide }

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

                // Compact section title: no badge or rule here, the card below
                // already supplies the structure.
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

            Item {
                id: _detailBody
                y:      _detailHeader.height + _detail._bodyGap
                width:  parent.width
                height: _detail._bodyH

            // ── APPEARANCE · Theme ──────────────────────────────────────
            Column {
                id: _secTheme
                width: parent.width
                spacing: 0
                visible: root._shownSection === "theme"

                property bool _showNeutralContent: false
                property bool _showMatuContent:    false
                Component.onCompleted: {
                    _secTheme._showNeutralContent = ShellSettings.neutralTheme
                    _secTheme._showMatuContent    = !ShellSettings.neutralTheme
                }
                Connections {
                    target: ShellSettings
                    function onNeutralThemeChanged() {
                        if (ShellSettings.reduceMotion) {
                            _secTheme._showNeutralContent = ShellSettings.neutralTheme
                            _secTheme._showMatuContent    = !ShellSettings.neutralTheme
                            return
                        }
                        if (ShellSettings.neutralTheme) {
                            _themeOpenMatuTimer.stop()
                            _secTheme._showMatuContent    = false
                            _themeOpenNeutralTimer.interval = Motion.fast + 20
                            _themeOpenNeutralTimer.restart()
                        } else {
                            _themeOpenNeutralTimer.stop()
                            _secTheme._showNeutralContent = false
                            _themeOpenMatuTimer.interval = Motion.fast + 20
                            _themeOpenMatuTimer.restart()
                        }
                    }
                }
                Timer { id: _themeOpenNeutralTimer; interval: Motion.fast + 20; onTriggered: _secTheme._showNeutralContent = true }
                Timer { id: _themeOpenMatuTimer;    interval: Motion.fast + 20; onTriggered: _secTheme._showMatuContent    = true }

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

                CollapsibleSection {
                    expanded: _secTheme._showNeutralContent

                    SectionLabel { label: "ACCENT" }
                    SettingsCard {

                        Item {
                            id: _accentPicker
                            width: parent.width
                            height: 110

                            readonly property real _accentL: 0.70
                            function _accentForHS(h, s) {
                                const c = Qt.hsla(h, s, _accentL, 1.0)
                                return "#" + root._hex2(c.r) + root._hex2(c.g) + root._hex2(c.b)
                            }
                            function _accentForHue(h) { return _accentForHS(h, 0.72) }
                            readonly property color _curColor: ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent
                            readonly property real  _curHue:   _curColor.hslHue < 0 ? 0 : _curColor.hslHue
                            readonly property real  _curSat:   isNaN(_curColor.hslSaturation) ? 0.72 : _curColor.hslSaturation

                            readonly property var _accents: [
                                { color: "#c0c8f0", name: "Lavender" },
                                { color: "#7aa2f7", name: "Blue"     },
                                { color: "#bb9af7", name: "Purple"   },
                                { color: "#73c7b5", name: "Teal"     },
                                { color: "#9ece6a", name: "Green"    },
                                { color: "#f7768e", name: "Rose"     },
                                { color: "#e0af68", name: "Amber"    }
                            ]

                            property string _hoverName: ""
                            // exact applied accent (matugen's when auto), for a precise readout
                            readonly property string _curHex: ShellSettings.neutralAccentAuto
                                ? ("#" + root._hex2(MatugenTheme.accent.r) + root._hex2(MatugenTheme.accent.g) + root._hex2(MatugenTheme.accent.b)).toUpperCase()
                                : ShellSettings.neutralAccent.toUpperCase()
                            readonly property string _activeName: {
                                if (ShellSettings.neutralAccentAuto) return "Auto  ·  " + _curHex
                                for (let i = 0; i < _accents.length; i++)
                                    if (_accents[i].color === ShellSettings.neutralAccent) return _accents[i].name + "  ·  " + _curHex
                                return _curHex
                            }
                            readonly property string _shownName: _hoverName.length > 0 ? _hoverName : _activeName

                            property real topRadius: 0
                            property real bottomRadius: 0
                            property real cardInset: 1

                            Text {
                                anchors.top:            parent.top; anchors.topMargin: 13
                                anchors.left:           parent.left; anchors.leftMargin: 12
                                anchors.right:          parent.right; anchors.rightMargin: 12
                                horizontalAlignment: Text.AlignRight
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
                                anchors.topMargin:  36
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

                                        // Centre dot — only on the selected swatch.
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

                            Item {
                                id: _hueStrip
                                anchors.top:       _swatchRow.bottom; anchors.topMargin: 14
                                anchors.left:      parent.left;  anchors.leftMargin:  12
                                anchors.right:     parent.right; anchors.rightMargin: 12
                                height: 14
                                opacity: ShellSettings.neutralAccentAuto ? 0.4 : 1.0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                activeFocusOnTab: true
                                Accessible.role: Accessible.Slider
                                Accessible.name: "Accent hue"
                                Accessible.description: _accentPicker._shownName
                                function _nudgeHue(dir: int, mult: int): void {
                                    const h = (_accentPicker._curHue + dir * 0.02 * mult + 1) % 1
                                    ShellSettings.neutralAccentAuto = false
                                    ShellSettings.neutralAccent = _accentPicker._accentForHS(h, _accentPicker._curSat)
                                }
                                Keys.onLeftPressed:  e => { _hueStrip._nudgeHue(-1, (e.modifiers & Qt.ShiftModifier) ? 5 : 1); e.accepted = true }
                                Keys.onRightPressed: e => { _hueStrip._nudgeHue(1,  (e.modifiers & Qt.ShiftModifier) ? 5 : 1); e.accepted = true }

                                Rectangle {
                                    anchors.fill: parent; radius: height / 2; antialiasing: true
                                    border.width: 1
                                    border.color: _hueStrip.activeFocus ? Theme.withAlpha(Theme.accent, 0.55) : Theme.menuControlLineHot
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.000; color: _accentPicker._accentForHue(0.000) }
                                        GradientStop { position: 0.167; color: _accentPicker._accentForHue(0.167) }
                                        GradientStop { position: 0.333; color: _accentPicker._accentForHue(0.333) }
                                        GradientStop { position: 0.500; color: _accentPicker._accentForHue(0.500) }
                                        GradientStop { position: 0.667; color: _accentPicker._accentForHue(0.667) }
                                        GradientStop { position: 0.833; color: _accentPicker._accentForHue(0.833) }
                                        GradientStop { position: 1.000; color: _accentPicker._accentForHue(1.000) }
                                    }
                                }
                                Rectangle {
                                    id: _hueThumb
                                    width: 16; height: 16; radius: 8; antialiasing: true
                                    y: (parent.height - height) / 2
                                    x: Math.round(_accentPicker._curHue * (_hueStrip.width - width))
                                    color: _accentPicker._curColor
                                    border.width: 2; border.color: Theme.text
                                    scale: _hueMa.pressed ? 1.18 : (_hueMa.containsMouse || _hueStrip.activeFocus ? 1.08 : 1.0); transformOrigin: Item.Center
                                    Behavior on x     { enabled: !_hueMa.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                                    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: _hueMa
                                    anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                                    cursorShape: Qt.PointingHandCursor; preventStealing: true; hoverEnabled: true
                                    function _set(mx) {
                                        const t = _hueThumb.width
                                        const h = Math.max(0, Math.min(1, (mx - t / 2) / Math.max(1, width - t)))
                                        ShellSettings.neutralAccentAuto = false
                                        ShellSettings.neutralAccent = _accentPicker._accentForHS(h, _accentPicker._curSat)
                                    }
                                    onPressed:         (m) => _set(m.x)
                                    onPositionChanged: (m) => { if (pressed) _set(m.x) }
                                }
                            }
                        }
                    }

                    SectionLabel { label: "BASE" }
                    SettingsCard {
                        ChoiceChipRow {
                            glyph: "󰃞"; label: "Background"
                            currentValue: ShellSettings.baseTone
                            model: [
                                { value: "charcoal", label: "Charcoal" },
                                { value: "black",    label: "Black"    }
                            ]
                            onChosen: (v) => ShellSettings.baseTone = v
                        }
                    }
                }

                // Neutral off -> the shell themes from matugen. Show the live
                // palette as proof it's working; if matugen isn't installed
                // these are the bundled fallback tones, called out as such.
                CollapsibleSection {
                    expanded: _secTheme._showMatuContent

                    SectionLabel { label: "PALETTE" }
                    SettingsCard {

                        Item {
                            id: _matuShowcase
                            width: parent.width
                            // Trailing 14 balances the top padding the readout/swatches sit under.
                            implicitHeight: _matuCol.y + _matuCol.implicitHeight + 16
                            height: implicitHeight

                            function _hex(c) { return ("#" + root._hex2(c.r) + root._hex2(c.g) + root._hex2(c.b)).toUpperCase() }

                            readonly property var _swatches: [
                                { c: MatugenTheme.accent,     n: "Accent"  },
                                { c: MatugenTheme.background, n: "Base"    },
                                { c: MatugenTheme.surface,    n: "Surface" },
                                { c: MatugenTheme.text,       n: "Text"    },
                                { c: MatugenTheme.error,      n: "Error"   },
                                { c: MatugenTheme.warning,    n: "Warning" },
                                { c: MatugenTheme.success,    n: "Success" }
                            ]

                            property string _hoverLabel: ""
                            readonly property string _source:  SystemTools.hasMatugen ? "Matugen" : "Fallback"
                            // Top-right readout: a hovered swatch's name·hex, else the source.
                            readonly property string _readout: _hoverLabel.length > 0 ? _hoverLabel : _source
                            property real topRadius: 0
                            property real bottomRadius: 0
                            property real cardInset: 1

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.top: parent.top
                                anchors.topMargin: 13
                                height: 34
                                spacing: 10

                                Rectangle {
                                    width: 34; height: 34; radius: 10
                                    antialiasing: true
                                    color: Theme.mix(Theme.menuControl, MatugenTheme.accent, 0.32)
                                    border.width: 1
                                    border.color: Theme.withAlpha(MatugenTheme.accent, 0.56)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰔎"
                                        color: MatugenTheme.accent
                                        font.family: Settings.font
                                        font.pixelSize: Settings.fontSize + 2
                                        renderType: Text.NativeRendering
                                    }
                                }

                                Column {
                                    width: parent.width - 44
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Text {
                                        width: parent.width
                                        text: _matuShowcase._readout
                                        color: Theme.text
                                        font.family: Settings.font
                                        font.pixelSize: Settings.fontSize
                                        font.weight: Font.DemiBold
                                        renderType: Text.NativeRendering
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: SystemTools.hasMatugen ? "Generated from wallpaper" : "Using bundled fallback colors"
                                        color: Theme.withAlpha(Theme.subtext, 0.62)
                                        font.family: Settings.font
                                        font.pixelSize: Settings.fontSize - 2
                                        renderType: Text.NativeRendering
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Column {
                                id: _matuCol
                                anchors.left:  parent.left;  anchors.leftMargin:  12
                                anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.top:   parent.top; anchors.topMargin: 62
                                spacing: 10

                                Row {
                                    width: parent.width
                                    height: 30
                                    spacing: Math.max(4, (width - 7 * 28) / 6)

                                    Repeater {
                                        model: _matuShowcase._swatches
                                        delegate: Rectangle {
                                            id: _msw
                                            required property var modelData
                                            required property int index
                                            readonly property bool _isAccent: index === 0
                                            readonly property string _label: modelData.n + "  ·  " + _matuShowcase._hex(modelData.c)
                                            width: 28; height: 30; radius: 8
                                            antialiasing: true
                                            color: modelData.c
                                            // Accent keeps a brighter rim so the headline colour
                                            // reads first; any swatch brightens on hover.
                                            border.width: 1
                                            border.color: _mswHover.hovered
                                                ? Theme.withAlpha(Theme.text, 0.7)
                                                : (_isAccent ? Theme.withAlpha(Theme.text, 0.5)
                                                             : Theme.menuControlLineHot)
                                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                                            scale: _mswHover.hovered ? 1.08 : 1.0
                                            transformOrigin: Item.Center
                                            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                            HoverHandler {
                                                id: _mswHover
                                                cursorShape: Qt.PointingHandCursor
                                                onHoveredChanged: _matuShowcase._hoverLabel =
                                                    hovered ? _msw._label
                                                            : (_matuShowcase._hoverLabel === _msw._label ? "" : _matuShowcase._hoverLabel)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── APPEARANCE · Motion ─────────────────────────────────────
            Column {
                id: _secMotion
                width: parent.width
                spacing: 0
                visible: root._shownSection === "motion"

                SettingsCard {
                    ToggleRow {
                        glyph: "󱖳"; label: "Reduce motion"
                        checked: ShellSettings.reduceMotion
                        onToggled: ShellSettings.reduceMotion = !ShellSettings.reduceMotion
                    }
                }

            }

            // ── APPEARANCE · Night Light ────────────────────────────────
            Column {
                id: _secNightLight
                width: parent.width
                spacing: 0
                visible: root._shownSection === "nightlight"

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
                HintText {
                    visible: NightLight.toolAvailable && !NightLight.enabled
                    text: "Night Light is off — turn it on from the menu to preview changes."
                }
            }

            // ── BAR · Surface ──────────────────────────────────────────
            Column {
                id: _secSurface
                width: parent.width
                spacing: 0
                visible: root._shownSection === "surface"

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

                SectionLabel { label: "FLOATING" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰖲"; label: "Floating bar"
                        description: "Detached surface with reserved input only over the visible bar"
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

            // ── BAR · Separators ───────────────────────────────────────
            Column {
                id: _secSeparators
                width: parent.width
                spacing: 0
                visible: root._shownSection === "separators"

                SettingsCard {
                    ToggleRow {
                        glyph: "󰡍"; label: "Compact spacing"
                        description: "Tighter widget groups with separators only between groups"
                        checked: ShellSettings.barCompact
                        onToggled: ShellSettings.barCompact = !ShellSettings.barCompact
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
                }

                // No marks are drawn under "None", so the opacity control is moot.
                SectionLabel { label: "APPEARANCE"; visible: ShellSettings.dotStyle !== "none" }
                SettingsCard {
                    visible: ShellSettings.dotStyle !== "none"
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

            // ── BAR · Underline ─────────────────────────────────────────
            Column {
                id: _secUnderline
                width: parent.width
                spacing: 0
                visible: root._shownSection === "underline"

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
                        ChoiceChipRow {
                            glyph: "󰃠"
                            label: ShellSettings.underlineGlow ? "Glow strength" : "Line strength"
                            currentValue: root._underlineBrightness
                            model: [
                                { value: "soft",   label: "Low" },
                                { value: "normal", label: "Med" },
                                { value: "bright", label: "High" }
                            ]
                            onChosen: (v) => root._setUnderlineBrightness(v)
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

            // ── WIDGETS · Clock ─────────────────────────────────────────
            Column {
                id: _secClock
                width: parent.width
                spacing: 0
                visible: root._shownSection === "clock"

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

            // ── WIDGETS · Workspaces ────────────────────────────────────
            Column {
                id: _secWorkspaces
                width: parent.width
                spacing: 0
                visible: root._shownSection === "workspaces"

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
                        description: "Shows up to three app icons on inactive occupied workspaces"
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

            // ── WIDGETS · Media ─────────────────────────────────────────
            Column {
                id: _secMedia
                width: parent.width
                spacing: 0
                visible: root._shownSection === "media"

                SettingsCard {
                    ToggleRow {
                        glyph: "󰎇"; label: "Show artist + title"
                        checked: ShellSettings.mediaWidgetFormat === "artist-title"
                        onToggled: ShellSettings.mediaWidgetFormat = (ShellSettings.mediaWidgetFormat === "artist-title" ? "title" : "artist-title")
                    }
                    ToggleRow {
                        glyph: "󰐊"; label: "Playback helper"
                        description: "Adds a play state glyph and track progress to the bar media widget"
                        checked: ShellSettings.mediaWidgetHelper
                        onToggled: ShellSettings.mediaWidgetHelper = !ShellSettings.mediaWidgetHelper
                    }
                }

                SectionLabel { label: "VISUALIZER" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰱐"; label: "Audio visualizer"; badge: "cava"
                        description: "Starts cava only while media is playing and the visualizer is visible"
                        checked: ShellSettings.mediaProgress
                        onToggled: ShellSettings.mediaProgress = !ShellSettings.mediaProgress
                        available: !SystemTools.ready || SystemTools.hasCava
                        dependsNote: SystemTools.ready ? "cava missing" : "Checking"
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.mediaProgress && SystemTools.hasCava
                        ChoiceChipRow {
                            glyph: "󰓅"; label: "Preset"
                            currentValue: ShellSettings.mediaVisualizerPreset
                            model: [
                                { value: "eco",      label: "Eco" },
                                { value: "balanced", label: "Bal" },
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
                    }
                }
            }

            // ── WIDGETS · Indicators ────────────────────────────────────
            Column {
                id: _secIndicators
                width: parent.width
                spacing: 0
                visible: root._shownSection === "indicators"

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

                SettingsCard {
                    ToggleRow {
                        glyph: "󰂃"; label: "Hide battery when charging or full"
                        checked: ShellSettings.batteryAutoHide
                        onToggled: ShellSettings.batteryAutoHide = !ShellSettings.batteryAutoHide
                        available: ShellSettings.barShowBattery && Battery.available
                        dependsNote: !Battery.available ? "No battery" : "Battery hidden"
                    }
                    ToggleRow {
                        glyph: "󰓅"; label: "Network speed"
                        checked: ShellSettings.networkTrafficStats
                        onToggled: ShellSettings.networkTrafficStats = !ShellSettings.networkTrafficStats
                        available: ShellSettings.barShowNetwork && Network.toolAvailable
                        dependsNote: !Network.toolAvailable ? "NetworkManager missing" : "Network hidden"
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.networkTrafficStats
                        ToggleRow {
                            glyph: "󰐃"; label: "Always show speed"
                            checked: ShellSettings.networkSpeedInline
                            onToggled: ShellSettings.networkSpeedInline = !ShellSettings.networkSpeedInline
                        }
                    }
                    ToggleRow {
                        glyph: "󰦝"; label: "Show connection under VPN"
                        checked: ShellSettings.netVpnShowLink
                        onToggled: ShellSettings.netVpnShowLink = !ShellSettings.netVpnShowLink
                        available: ShellSettings.barShowNetwork && Network.toolAvailable
                        dependsNote: !Network.toolAvailable ? "NetworkManager missing" : "Network hidden"
                    }
                }
            }

            // ── NOTIFICATIONS · Popups ──────────────────────────────────
            Column {
                id: _secPopups
                width: parent.width
                spacing: 0
                visible: root._shownSection === "popups"

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

            }

            // ── NOTIFICATIONS · OSD ─────────────────────────────────────
            Column {
                id: _secOsd
                width: parent.width
                spacing: 0
                visible: root._shownSection === "osd"

                SettingsCard {
                    ToggleRow {
                        glyph: "󱀅"; label: "Show OSD"
                        checked: ShellSettings.osdEnabled
                        onToggled: ShellSettings.osdEnabled = !ShellSettings.osdEnabled
                    }
                    // Mode: floating pill vs bar-inline. Drives which sub-options apply.
                    ToggleRow {
                        glyph: "󰀱"; label: "Show in bar"; badge: "beta"
                        description: "Uses the overlay monitor's bar center instead of the floating OSD pill"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdBarIntegrated
                        onToggled: ShellSettings.osdBarIntegrated = !ShellSettings.osdBarIntegrated
                    }
                    ToggleRow {
                        glyph: "󰖲"; label: "Match bar shape"
                        enabled: ShellSettings.osdEnabled && !ShellSettings.osdBarIntegrated
                        checked: ShellSettings.osdMatchBar
                        onToggled: ShellSettings.osdMatchBar = !ShellSettings.osdMatchBar
                        description: "Pill takes the bar's height and corner radius"
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
                }

                SectionLabel { label: "VOLUME" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰓎"; label: "Volume emphasis"
                        description: "Warm tint and a soft shimmer as volume nears maximum"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdVolumeTint
                        onToggled: ShellSettings.osdVolumeTint = !ShellSettings.osdVolumeTint
                    }
                }
            }

            // ── NOTIFICATIONS · Warnings ────────────────────────────────
            Column {
                id: _secWarnings
                width: parent.width
                spacing: 0
                visible: root._shownSection === "warnings"

                SectionLabel { label: "BATTERY"; first: true }
                SettingsCard {
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
                        enabled: ShellSettings.osdEnabled && Battery.available
                        available: Battery.available
                        checked: ShellSettings.osdChargedNotify
                        onToggled: ShellSettings.osdChargedNotify = !ShellSettings.osdChargedNotify
                        dependsNote: !Battery.available ? "No battery" : "OSD off"
                    }
                }

                SectionLabel { label: "CPU TEMPERATURE" }
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

            // ── SYSTEM ──────────────────────────────────────────────────
            Column {
                id: _secSystem
                width: parent.width
                spacing: 0
                visible: root._shownSection === "system"

                SettingsCard {
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
                }

                SectionLabel { label: "MONITORS"; visible: Quickshell.screens.length > 1 }
                SettingsCard {
                    visible: Quickshell.screens.length > 1
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
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 2
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

            // ── SYSTEM · Updates ────────────────────────────────────────
            Column {
                id: _secUpdates
                width: parent.width
                spacing: 0
                visible: root._shownSection === "updates"

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

                        primaryLabel: ShellUpdate.applying ? "Installing…"
                            : ShellUpdate.checking ? "Checking…"
                            : ShellUpdate.pending ? "Install" : "Check"
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
                        description: "Counts pending packages and shows a badge in the bar"
                        checked: ShellSettings.updatesWidget
                        onToggled: ShellSettings.updatesWidget = !ShellSettings.updatesWidget
                        available: !SystemTools.ready || Updates.supported
                        dependsNote: "No package manager"
                    }
                }

                SectionLabel { label: "AUTOMATIC CHECKS" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰥔"; label: "Daily Silere update check"
                        checked: ShellUpdate.timerEnabled
                        enabled: !ShellUpdate.timerBusy
                        available: ShellUpdate.timerSupported
                        dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
                        onToggled: ShellUpdate.setTimerEnabled(!ShellUpdate.timerEnabled)
                    }
                    HintText { text: "Checks only update the badge — nothing installs without your confirmation." }
                }
            }
            }   // _detailBody
    }
}
