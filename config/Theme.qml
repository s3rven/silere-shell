pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _n: ShellSettings.neutralTheme

    // neutral base tones (only the dark base changes); text/accent/status shared across tones and matugen. selectable in Appearance.
    // surfaces step clearly above the base (sidebar→card→surface, no clustering) with a whisper of cool in blue — graphite not dead grey, without a visible tint.
    readonly property var _tones: ({
        charcoal: { background: "#090a0c", surface: "#17191d", subtext: "#a0a3aa" },
        black:    { background: "#030303", surface: "#101114", subtext: "#9699a0" }
    })
    // custom tone derives surface/subtext from the picked base so elevation steps stay intact
    readonly property var _pal: {
        if (ShellSettings.baseTone === "custom") {
            const cb = Qt.color(ShellSettings.customBase)
            return { background: cb, surface: mix(cb, "#f2f4f8", 0.060), subtext: mix("#a0a3aa", cb, 0.10) }
        }
        return _tones[ShellSettings.baseTone] ?? _tones.charcoal
    }

    // wallpaper mode can accent from any material role (secondary/tertiary land in success/warning)
    readonly property color _matuAccent: ShellSettings.matugenAccentRole === "secondary" ? MatugenTheme.success
                                       : ShellSettings.matugenAccentRole === "tertiary"  ? MatugenTheme.warning
                                       : MatugenTheme.accent

    readonly property color background: _n ? _pal.background : MatugenTheme.background
    readonly property color surface:    _n ? _pal.surface   : MatugenTheme.surface
    readonly property color text:       _n ? "#f2f4f8" : MatugenTheme.text
    readonly property color subtext:    _n ? _pal.subtext   : MatugenTheme.subtext
    readonly property color accent:     _n ? (ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent) : _matuAccent
    readonly property color error:      _n ? "#f7768e" : MatugenTheme.error
    readonly property color warning:    _n ? "#e0af68" : MatugenTheme.warning
    readonly property color success:    _n ? "#9ece6a" : MatugenTheme.success

    // neutral mode keeps chrome neutral — accent only for active/focus/selected/status, not tinting every pane
    readonly property color outline: _n ? withAlpha(subtext, 0.14)
                                        : withAlpha(mix(subtext, accent, 0.22), 0.17)

    readonly property color panel: withAlpha(background, ShellSettings.barOpacity)
    readonly property color popup: background

    // tonal elevation: dark-mode depth reads lighter-on-darker, so menu surfaces step UP from base (~6/8% toward text). cards/panels = L1, interactive tiles a hair higher.
    readonly property color menuPane:        _n ? mix(background, text, 0.030)
                                                : mix(background, surface, 0.18)
    readonly property color menuCard:        _n ? mix(background, text, 0.060)
                                                : mix(background, text, 0.07)
    readonly property color menuCardBorder:  _n ? withAlpha(subtext, 0.105)
                                                : withAlpha(mix(subtext, accent, 0.22), 0.17)
    readonly property color menuDivider:     _n ? withAlpha(subtext, 0.075)
                                                : withAlpha(subtext, 0.085)
    readonly property color menuHover:       accent
    readonly property color menuControl:     _n ? mix(background, text, 0.090)
                                                : mix(background, text, 0.09)
    readonly property color menuControlLine: _n ? withAlpha(subtext, 0.115)
                                                : withAlpha(subtext, 0.135)
    readonly property color menuControlLineHot: _n ? withAlpha(subtext, 0.18)
                                                   : withAlpha(mix(subtext, accent, 0.18), 0.20)
    readonly property color menuTrack:       _n ? withAlpha(subtext, 0.14)
                                                : withAlpha(subtext, 0.16)
    readonly property color menuTextMuted:   mix(subtext, text, _n ? 0.30 : 0.24)
    readonly property color menuTextFaint:   mix(subtext, text, _n ? 0.15 : 0.10)

    readonly property int radiusPanel:   14
    readonly property int radiusCard:    12
    readonly property int radiusControl: 10

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
