import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property string _paletteNote: !SystemTools.ready ? ""
        : !SystemTools.hasMatugen
            ? "Wallpaper theming needs matugen installed. These are Silere's bundled colors."
            : MatugenTheme.usingFallback
                ? "Matugen has not written a palette yet, so these are Silere's bundled colors. Re-run the installer, then set a wallpaper."
                : MatugenTheme.paletteStale
                    ? "The palette file could not be read, so these are the last colors that loaded. Check your matugen template."
                    : ""

    function _hex2(v): string {
        const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }

    SectionLabel { label: "THEME MODE"; first: true }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰉦"; label: "Source"
            currentValue: ShellSettings.neutralTheme ? "neutral" : "wallpaper"
            model: [
                { value: "neutral",   label: "Custom"    },
                { value: "wallpaper", label: "Wallpaper" }
            ]
            onChosen: (v) => ShellSettings.neutralTheme = (v === "neutral")
        }
    }

    SectionLabel { label: "PALETTE" }
    SettingsCard {
        CollapsibleSection {
            expanded: ShellSettings.neutralTheme
            symmetric: true

            Item {
                id: _accentPicker
                width: parent.width
                // derived, not a constant: the swatch row and title grow with uiScale and a fixed box clips them.
                // same formula as SwatchPickerRow._headerH so this header shares the neighbouring rows' rhythm
                readonly property int _titleH: 4 * Math.ceil(Math.max(40,
                    _accentGlyph.implicitHeight + 12, _accentTitle.implicitHeight + 12) / 4)
                readonly property int _swatchH: Metrics.rowHeightFor(32)
                height: _titleH + _swatchH + _customStrips.height + 8

                // the palette's own working point: presets measure L* 68-73, C* 25-35
                readonly property real _accentL: 70.8
                readonly property real _accentCMax: 38
                function _accentForCh(hue01, c01): string {
                    const c = Theme.lchColor(_accentPicker._accentL,
                        c01 * _accentPicker._accentCMax, hue01 * 360)
                    return "#" + root._hex2(c.r) + root._hex2(c.g) + root._hex2(c.b)
                }
                readonly property color _curColor: ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent
                readonly property var  _curLch:  Theme.lchOf(_curColor)

                // the strips own hue and intensity; the stored hex is only their output.
                // reading both back out of one 8-bit colour made each axis inherit the
                // other's rounding, and the untouched thumb animated that drift
                property real _hueMemo: 0
                property real _satMemo: 0
                property bool _stripWrite: false
                // an 8-bit near-grey carries no hue: below this the recovered angle is noise
                readonly property real _hueFloorC: 3.0

                function _syncFromColor(): void {
                    const l = _accentPicker._curLch
                    if (l.C >= _accentPicker._hueFloorC) _accentPicker._hueMemo = l.h / 360
                    _accentPicker._satMemo = Math.min(1, l.C / _accentPicker._accentCMax)
                }
                function _writeStrips(hue01: real, sat01: real): void {
                    _accentPicker._hueMemo = hue01
                    _accentPicker._satMemo = sat01
                    _accentPicker._stripWrite = true
                    ShellSettings.batch(() => {
                        ShellSettings.neutralAccentAuto = false
                        ShellSettings.neutralAccent = _accentPicker._accentForCh(hue01, sat01)
                    })
                    _accentPicker._stripWrite = false
                }
                on_CurColorChanged: if (!_stripWrite) _syncFromColor()
                Component.onCompleted: _syncFromColor()

                readonly property real _curHue: _hueMemo
                readonly property real _curSat: _satMemo
                // the hue rail must stay readable at zero intensity, where the colour is grey
                readonly property real _railC: Math.max(_satMemo * _accentCMax, 20)
                // line the rails up with the swatch run, not the viewport that scrolls it
                readonly property int _railX: 12 + _swatchRow.edgePadding

                readonly property var _options: [
                    { auto: true,  custom: false, color: "",        name: "Auto"   },
                    { auto: false, custom: false, color: "#b8bdd8", name: "Mist"   },
                    { auto: false, custom: false, color: "#82aee5", name: "Blue"   },
                    { auto: false, custom: false, color: "#b79bd7", name: "Violet" },
                    { auto: false, custom: false, color: "#78bfb5", name: "Teal"   },
                    { auto: false, custom: false, color: "#94bd8b", name: "Green"  },
                    { auto: false, custom: false, color: "#dd92a2", name: "Rose"   },
                    { auto: false, custom: false, color: "#d4ad77", name: "Amber"  },
                    { auto: false, custom: true,  color: "",        name: "Mix"    }
                ]
                readonly property int _customIndex: _options.length - 1
                readonly property int _presetIndex: {
                    if (ShellSettings.neutralAccentAuto) return 0
                    const current = String(ShellSettings.neutralAccent).toLowerCase()
                    for (let i = 1; i < _customIndex; i++)
                        if (String(_options[i].color).toLowerCase() === current) return i
                    return -1
                }
                // tapping Custom keeps the strips open even while the colour still equals a preset
                property bool _customPinned: false
                readonly property bool _customOpen: !ShellSettings.neutralAccentAuto
                    && (_customPinned || _presetIndex < 0)
                readonly property int _activeIndex: _customOpen ? _customIndex : _presetIndex

                readonly property var _swColors: _options.map(o => o.auto ? MatugenTheme.accent
                    : o.custom ? _accentPicker._curColor : o.color)
                // dependent bindings settle in stages, so an index can be transiently out of
                // range here even though no steady state produces one
                function _nameAt(i: int): string {
                    const o = i >= 0 && i < _options.length ? _options[i] : null
                    return o ? o.name : ""
                }
                // a preset reads by name; a custom colour has none, so show what it actually is
                readonly property string _activeName: _customOpen
                    ? String(ShellSettings.neutralAccent).toUpperCase()
                    : _nameAt(_activeIndex)
                readonly property string _shownName: _swatchRow.hoveredIndex >= 0
                    ? _nameAt(_swatchRow.hoveredIndex) : _activeName
                readonly property color  _shownColor: _swatchRow.hoveredIndex >= 0
                    && _swatchRow.hoveredIndex < _swColors.length
                    ? _swColors[_swatchRow.hoveredIndex] : _curColor

                // glyph cell and margins mirror SwatchPickerRow's header, or this stacked block
                // sits 26px off the label column every neighbouring row shares
                ShellText {
                    id: _accentGlyph
                    anchors.left:   parent.left; anchors.leftMargin: 14
                    y: Math.round((_accentPicker._titleH - height) / 2)
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text:           "󰔎"
                    color:          Theme.withAlpha(Theme.subtext, 0.85)
                    font.pixelSize: Settings.iconSize + 2
                }
                ShellText {
                    id: _accentTitle
                    anchors.left:           _accentGlyph.right; anchors.leftMargin: 10
                    anchors.verticalCenter: _accentGlyph.verticalCenter
                    anchors.right:          _accentReadout.left; anchors.rightMargin: 10
                    text:           "Accent"
                    color:          Theme.withAlpha(Theme.text, 0.85)
                    font.pixelSize: Settings.fontSize
                    elide:          Text.ElideRight
                }
                ShellText {
                    id: _accentReadout
                    anchors.right:          parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: _accentGlyph.verticalCenter
                    width:                  Math.min(84, implicitWidth)
                    horizontalAlignment:    Text.AlignRight
                    text:           _accentPicker._shownName
                    color:          ShellSettings.highContrast
                        ? Theme.withAlpha(Theme.subtext, 0.7)
                        : Theme.mix(Theme.subtext, _accentPicker._shownColor, 0.62)
                    ColorFade on color {}
                    font.pixelSize: Settings.fontCaption
                    elide:          Text.ElideRight
                }

                ShellFlickable {
                    id: _swatchViewport
                    anchors.top:        parent.top
                    anchors.topMargin:  _accentPicker._titleH
                    anchors.left:       parent.left;  anchors.leftMargin:  12
                    anchors.right:      parent.right; anchors.rightMargin: 12
                    height: _accentPicker._swatchH
                    contentWidth: _swatchRow.width
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    interactive: contentWidth > width + 1

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
                        groupLabel: "Accent"
                        options: _accentPicker._options
                        colors:  _accentPicker._swColors
                        activeIndex: _accentPicker._activeIndex
                        // timer, not Qt.callLater: this dies with the section, where a deferred
                        // call survives the swap and fires against a destroyed viewport
                        onActiveIndexChanged: _revealDefer.restart()
                        Timer {
                            id: _revealDefer
                            interval: 0
                            onTriggered: _swatchViewport.revealIndex(_swatchRow.activeIndex)
                        }
                        onPicked: (i) => {
                            const opt = _accentPicker._options[i]
                            _accentPicker._customPinned = !!opt.custom
                            ShellSettings.batch(() => {
                                if (opt.auto) {
                                    ShellSettings.neutralAccentAuto = true
                                    return
                                }
                                ShellSettings.neutralAccentAuto = false
                                // Custom opens on the colour already stored; only a preset overwrites it
                                if (!opt.custom) ShellSettings.neutralAccent = opt.color
                            })
                        }
                    }
                }

                Item {
                    id: _customStrips
                    anchors.top:   _swatchViewport.bottom
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    clip: true
                    height: _accentPicker._customOpen ? _stripCol.implicitHeight : 0
                    visible: height > 0.5
                    enabled: _accentPicker._customOpen

                    Disclosure on height { expanded: _accentPicker._customOpen }

                    Column {
                        id: _stripCol
                        width: parent.width
                        topPadding: 4
                        spacing: 4
                        opacity: _accentPicker._customOpen ? 1.0 : 0.0
                        MotionBehavior on opacity {
                            NumberAnimation {
                                duration: Motion.fast
                                easing.type: _accentPicker._customOpen ? Easing.OutCubic : Easing.InCubic
                            }
                        }

                        GradientSlider {
                            id: _hueStrip
                            x: _accentPicker._railX
                            width: Math.max(1, parent.width - _accentPicker._railX * 2)
                            height: 24
                            position: _accentPicker._curHue
                            thumbColor: _accentPicker._curColor
                            trackGradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.000; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC,   0) }
                                GradientStop { position: 0.167; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC,  60) }
                                GradientStop { position: 0.333; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC, 120) }
                                GradientStop { position: 0.500; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC, 180) }
                                GradientStop { position: 0.667; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC, 240) }
                                GradientStop { position: 0.833; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC, 300) }
                                GradientStop { position: 1.000; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._railC, 360) }
                            }
                            onPicked: hue => _accentPicker._writeStrips(hue, _accentPicker._satMemo)
                        }

                        GradientSlider {
                            id: _satStrip
                            x: _accentPicker._railX
                            width: Math.max(1, parent.width - _accentPicker._railX * 2)
                            height: 24
                            position: _accentPicker._curSat
                            thumbColor: _accentPicker._curColor
                            wraps: false
                            displayScale: 100
                            valueUnit: "percent"
                            wheelKey: "accent-chroma"
                            trackGradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Theme.lchColor(_accentPicker._accentL, 0, _accentPicker._curHue * 360) }
                                GradientStop { position: 1.0; color: Theme.lchColor(_accentPicker._accentL, _accentPicker._accentCMax, _accentPicker._curHue * 360) }
                            }
                            onPicked: sat => _accentPicker._writeStrips(_accentPicker._hueMemo, sat)
                        }
                    }
                }
            }

        }

        CollapsibleSection {
            expanded: !ShellSettings.neutralTheme
            symmetric: true

            SwatchPickerRow {
                glyph: "󰔎"; label: "Accent"
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

            HintText {
                visible: root._paletteNote.length > 0
                text: root._paletteNote
            }
        }

        // one row for both sources: each depth was solved to land on the matching neutral
        // tone's luminance, so the three names mean the same thing on either side. Keeping it
        // outside both groups means a Source switch recolours it instead of collapsing it.
        SwatchPickerRow {
            readonly property bool _neutral: ShellSettings.neutralTheme
            glyph: "󰏘"; label: "Base"
            options: _neutral
                ? [{ value: "black",  name: "Black" },
                   { value: "charcoal", name: "Charcoal" },
                   { value: "graphite", name: "Graphite" }]
                : [{ value: "deeper", name: "Black" },
                   { value: "deep",   name: "Charcoal" },
                   { value: "none",   name: "Graphite" }]
            // preview Theme.background exactly: the elevated surface read lighter than the applied color
            colors: _neutral
                ? [Theme._tones.black.background,
                   Theme._tones.charcoal.background,
                   Theme._tones.graphite.background]
                : [Theme.mix(MatugenTheme.background, "#000000", Theme._depths.deeper),
                   Theme.mix(MatugenTheme.background, "#000000", Theme._depths.deep),
                   Theme.mix(MatugenTheme.background, "#000000", Theme._depths.none)]
            activeIndex: options.findIndex(o => o.value ===
                (_neutral ? ShellSettings.baseTone : ShellSettings.matugenDepth))
            ringColor: Theme.accent
            onPicked: (i) => {
                if (_neutral) ShellSettings.baseTone = options[i].value
                else ShellSettings.matugenDepth = options[i].value
            }
        }

        SliderRow {
            glyph: "󰃇"; label: "Outline strength"
            key: "outlineStrength"
            displayValue: Math.round(ShellSettings.outlineStrength * 100) + "%"
        }
    }
}
