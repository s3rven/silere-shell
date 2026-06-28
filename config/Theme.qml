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
        charcoal: { background: "#0e0e12", surface: "#19191f", subtext: "#71717a" },
        black:    { background: "#000000", surface: "#0f0f14", subtext: "#6d6d75" }
    })
    readonly property var _pal: _tones[ShellSettings.baseTone] ?? _tones.charcoal

    readonly property color background: _n ? _pal.background : MatugenTheme.background
    readonly property color surface:    _n ? _pal.surface   : MatugenTheme.surface
    readonly property color text:       _n ? "#ebebeb" : MatugenTheme.text
    readonly property color subtext:    _n ? _pal.subtext   : MatugenTheme.subtext
    readonly property color accent:     _n ? (ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent) : MatugenTheme.accent
    readonly property color error:      _n ? "#f7768e" : MatugenTheme.error
    readonly property color warning:    _n ? "#e0af68" : MatugenTheme.warning
    readonly property color success:    _n ? "#9ece6a" : MatugenTheme.success

    // Chrome outline for top-level panels/popups: subtext with a whisper of
    // accent, so the frame follows the theme instead of reading flat grey.
    readonly property color outline: withAlpha(mix(subtext, accent, 0.30), 0.20)

    readonly property color panel: withAlpha(background, ShellSettings.barOpacity)
    readonly property color popup: background

    readonly property color menuCard:        mix(surface, background, 0.16)
    readonly property color menuCardBorder:  withAlpha(mix(subtext, accent, 0.28), 0.24)
    readonly property color menuDivider:     withAlpha(subtext, 0.10)
    readonly property color menuHover:       accent
    readonly property color menuControl:     mix(surface, background, 0.06)
    readonly property color menuControlLine: withAlpha(subtext, 0.18)
    readonly property color menuTrack:       withAlpha(subtext, 0.16)

    readonly property int radiusPanel:   14
    readonly property int radiusCard:    12
    readonly property int radiusControl: 10

    // menu spacing on the 4px grid: section > item > tight
    readonly property int gapSection: 12
    readonly property int gapItem:    8
    readonly property int gapTight:   4

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

    // Notification-row surface: elevated card tone, error-tinted when critical,
    // lifted on hover. Shared by live popups and the history list so they match.
    function rowFill(hovered: bool, danger: bool): color {
        return danger ? mix(surface, error,   hovered ? 0.17 : 0.12)
                      : mix(surface, subtext, hovered ? 0.11 : 0.06)
    }
}
