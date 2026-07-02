pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _n: ShellSettings.neutralTheme

    // Neutral base tones, only the dark base changes; text/accent/status are
    // shared across tones (and with matugen). Selectable in Appearance.
    // Surfaces sit a clear step above the base (so sidebar→card→surface layer
    // instead of clustering) with a whisper of cool in the blue channel — reads
    // as graphite rather than dead grey, without tipping into a visible tint.
    readonly property var _tones: ({
        charcoal: { background: "#090a0c", surface: "#17191d", subtext: "#a0a3aa" },
        black:    { background: "#030303", surface: "#101114", subtext: "#9699a0" }
    })
    readonly property var _pal: _tones[ShellSettings.baseTone] ?? _tones.charcoal

    readonly property color background: _n ? _pal.background : MatugenTheme.background
    readonly property color surface:    _n ? _pal.surface   : MatugenTheme.surface
    readonly property color text:       _n ? "#f2f4f8" : MatugenTheme.text
    readonly property color subtext:    _n ? _pal.subtext   : MatugenTheme.subtext
    readonly property color accent:     _n ? (ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent) : MatugenTheme.accent
    readonly property color error:      _n ? "#f7768e" : MatugenTheme.error
    readonly property color warning:    _n ? "#e0af68" : MatugenTheme.warning
    readonly property color success:    _n ? "#9ece6a" : MatugenTheme.success

    // Neutral mode keeps chrome genuinely neutral. Accent is reserved for active
    // state, focus, selected controls, and status rather than tinting every pane.
    readonly property color outline: _n ? withAlpha(subtext, 0.14)
                                        : withAlpha(mix(subtext, accent, 0.22), 0.17)

    readonly property color panel: withAlpha(background, ShellSettings.barOpacity)
    readonly property color popup: background

    // Tonal elevation: in dark mode depth reads from lighter-on-darker, so menu
    // surfaces step UP from the base (~6/8% toward text) instead of blending into
    // it. Cards/panels = L1, interactive tiles = a hair higher.
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

    // Linear blend between two opaque colors. Use this for "tinted surface"
    // looks instead of withAlpha(), keeps the result fully opaque so it
    // doesn't pick up whatever sits behind the panel.
    function mix(base: color, tint: color, a: real): color {
        return Qt.rgba(
            base.r * (1 - a) + tint.r * a,
            base.g * (1 - a) + tint.g * a,
            base.b * (1 - a) + tint.b * a,
            1.0
        )
    }

    // Notification-row surface: elevated menu/card tone, error-tinted when
    // critical, lifted on hover. Shared by live popups and the history list so
    // neutral mode does not fall back to the flatter generic surface colours.
    function rowFill(hovered: bool, danger: bool): color {
        return danger ? mix(menuCard, error, hovered ? 0.18 : 0.13)
                      : hovered ? mix(menuCard, text, 0.045) : menuCard
    }
}
