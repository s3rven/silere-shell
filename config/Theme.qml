pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _n: ShellSettings.neutralTheme
    readonly property bool _hc: ShellSettings.highContrast

    // neutral base tones; surfaces step above a cool graphite base without reading blue.
    readonly property var _tones: ({
        black:    { background: "#030405", surface: "#111216", subtext: "#9296a1" },
        charcoal: { background: "#0b0c10", surface: "#191b21", subtext: "#9a9eaa" },
        graphite: { background: "#111319", surface: "#20232b", subtext: "#a3a7b2" }
    })
    readonly property var _pal: _tones[ShellSettings.baseTone] ?? _tones.charcoal

    // wallpaper mode can accent from any material role (secondary/tertiary land in success/warning)
    readonly property color _matuAccent: ShellSettings.matugenAccentRole === "secondary" ? MatugenTheme.success
                                       : ShellSettings.matugenAccentRole === "tertiary"  ? MatugenTheme.warning
                                       : MatugenTheme.accent

    readonly property color _surfaceBase: _n ? _pal.surface   : MatugenTheme.surface
    readonly property color _textBase:    _n ? "#e9eaf0"      : MatugenTheme.text
    readonly property color _subtextBase: _n ? _pal.subtext   : MatugenTheme.subtext

    readonly property color background: _n ? _pal.background : MatugenTheme.background
    readonly property color text:       _hc ? "#ffffff" : _textBase
    readonly property color subtext:    _hc ? mix(_subtextBase, text, 0.32) : _subtextBase
    readonly property color surface:    _hc ? mix(_surfaceBase, text, 0.035) : _surfaceBase
    readonly property color accent:     _n ? (ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent) : _matuAccent
    readonly property color error:      _n ? "#dd92a2" : MatugenTheme.error
    readonly property color warning:    _n ? "#d4ad77" : MatugenTheme.warning
    readonly property color success:    _n ? "#94bd8b" : MatugenTheme.success

    // outlineStrength scales every line tone in one place; alphas below stay the tuned baselines
    readonly property real _lineK: ShellSettings.outlineStrength
    function lineAlpha(a: real): real { return Math.min(1, a * _lineK) }

    // neutral mode keeps chrome neutral — accent only for active/focus/selected/status, not tinting every pane
    readonly property color outline: _hc ? withAlpha(text, lineAlpha(0.36))
                                        : _n ? withAlpha(subtext, lineAlpha(0.14))
                                             : withAlpha(mix(subtext, accent, 0.22), lineAlpha(0.17))

    // shared by Dot's marks and the window title's inline delimiter; dotOpacity is its only control
    readonly property color barSeparator: withAlpha(_n ? subtext : mix(subtext, accent, 0.10),
                                                    ShellSettings.dotOpacity)

    readonly property color panel: withAlpha(background,
        _hc ? Math.max(0.90, ShellSettings.barOpacity) : ShellSettings.barOpacity)
    readonly property color popup: background

    // tonal elevation: dark-mode depth reads lighter-on-darker, so menu surfaces step UP from base (~6/8% toward text). cards/panels = L1, interactive tiles a hair higher.
    readonly property color menuPane:        _n ? mix(background, text, _hc ? 0.050 : 0.030)
                                                : mix(background, _hc ? text : surface, _hc ? 0.055 : 0.18)
    readonly property color menuCard:        _n ? mix(background, text, _hc ? 0.090 : 0.060)
                                                : mix(background, text, _hc ? 0.100 : 0.07)
    readonly property color menuCardBorder:  _hc ? withAlpha(text, lineAlpha(0.22))
                                                : _n ? withAlpha(subtext, lineAlpha(0.105))
                                                     : withAlpha(mix(subtext, accent, 0.22), lineAlpha(0.17))
    readonly property color menuDivider:     _hc ? withAlpha(text, lineAlpha(0.16))
                                                : _n ? withAlpha(subtext, lineAlpha(0.075))
                                                     : withAlpha(subtext, lineAlpha(0.085))
    readonly property color menuHover:       accent
    readonly property color menuControl:     _n ? mix(background, text, _hc ? 0.125 : 0.090)
                                                : mix(background, text, _hc ? 0.130 : 0.09)
    readonly property color menuControlLine: _hc ? withAlpha(text, lineAlpha(0.24))
                                                : _n ? withAlpha(subtext, lineAlpha(0.115))
                                                     : withAlpha(subtext, lineAlpha(0.135))
    readonly property color menuControlLineHot: _hc ? withAlpha(accent, lineAlpha(0.45))
                                                   : _n ? withAlpha(subtext, lineAlpha(0.18))
                                                        : withAlpha(mix(subtext, accent, 0.18), lineAlpha(0.20))
    readonly property color menuTrack:       _hc ? withAlpha(text, 0.22)
                                                : _n ? withAlpha(subtext, 0.14)
                                                     : withAlpha(subtext, 0.16)
    readonly property color menuTextMuted:   mix(subtext, text, _hc ? 0.45 : (_n ? 0.30 : 0.24))
    readonly property color menuTextFaint:   mix(subtext, text, _hc ? 0.25 : (_n ? 0.15 : 0.10))

    readonly property int radiusPanel:   14
    readonly property int radiusCard:    12
    readonly property int radiusControl: 10
    // floating panels follow the bar's corner (flat bar → sharp, custom radius → match); attached bar keeps the default
    readonly property int surfaceRadius: ShellSettings.barFloating
        ? (ShellSettings.barCornerStyle === "flat" ? 0 : ShellSettings.barRadius)
        : radiusPanel

    readonly property int gapSection: 12

    function withAlpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // linear blend of two opaque colors — use for "tinted surface" instead of withAlpha(); stays opaque so it doesn't pick up what's behind the panel
    function mix(base: color, tint: color, a: real): color {
        return Qt.rgba(
            base.r * (1 - a) + tint.r * a,
            base.g * (1 - a) + tint.g * a,
            base.b * (1 - a) + tint.b * a,
            1.0
        )
    }

    // notification-row surface: elevated menu/card tone, error-tinted when critical, lifted on hover. shared by popups + history so neutral mode doesn't fall back to the flatter generic surface.
    function rowFill(hovered: bool, danger: bool): color {
        return danger ? mix(menuCard, error, hovered ? 0.18 : 0.13)
                      : hovered ? mix(menuCard, text, 0.045) : menuCard
    }
}
