import QtQuick
import "../../config"
import "../../services"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    function _hex2(v) {
        const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }

    SectionLabel { label: "THEME MODE"; first: true }
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

    SectionLabel { label: "PALETTE" }
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
                        groupLabel: "Accent"
                        options: _accentPicker._options
                        colors:  _accentPicker._swColors
                        activeIndex: _accentPicker._activeIndex
                        onActiveIndexChanged: Qt.callLater(function() {
                            _swatchViewport.revealIndex(_swatchRow.activeIndex)
                        })
                        onFocusMoved: (i) => _swatchViewport.revealIndex(i)
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
