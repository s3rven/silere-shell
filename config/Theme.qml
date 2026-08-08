pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _n: ShellSettings.neutralTheme
    readonly property bool _hc: ShellSettings.highContrast

    readonly property var _tones: ({
        black:    { background: "#030405", surface: "#121214", subtext: "#9296a1" },
        charcoal: { background: "#0b0c0e", surface: "#1b1b1c", subtext: "#9a9eaa" },
        graphite: { background: "#131315", surface: "#232324", subtext: "#a3a7b2" }
    })
    readonly property var _pal: _tones[ShellSettings.baseTone] ?? _tones.charcoal

    readonly property color _matuAccent: ShellSettings.matugenAccentRole === "secondary" ? MatugenTheme.success
                                       : ShellSettings.matugenAccentRole === "tertiary"  ? MatugenTheme.warning
                                       : MatugenTheme.accent

    // matugen's own base lands near the graphite tone; these sink it to charcoal and to black
    readonly property var _depths: ({ none: 0.0, deep: 0.38, deeper: 0.80 })
    readonly property real _depthK: _depths[ShellSettings.matugenDepth] ?? 0.0
    // surface sinks slower than background, or the elevation separation flattens out
    readonly property color _matuBg:      mix(MatugenTheme.background, "#000000", _depthK)
    readonly property color _matuSurface: mix(MatugenTheme.surface,    "#000000", _depthK * 0.6)

    readonly property color _surfaceBase: _n ? _pal.surface   : _matuSurface
    readonly property color _textBase:    _n ? "#e9eaf0"      : MatugenTheme.text
    // on_surface_variant sits only 1.31:1 from on_surface, so secondary text reads as loud as
    // primary; sinking it toward the base restores the neutral palette's 2.2:1 split
    readonly property color _subtextBase: _n ? _pal.subtext
                                             : mix(MatugenTheme.subtext, _matuBg, 0.25)

    readonly property color background: _n ? _pal.background : _matuBg
    readonly property color text:       _hc ? "#ffffff" : _textBase
    readonly property color subtext:    _hc ? mix(_subtextBase, text, 0.32) : _subtextBase
    readonly property color surface:    _hc ? mix(_surfaceBase, text, 0.035) : _surfaceBase
    readonly property color accent:     _n ? (ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent) : _matuAccent
    // matugen warning/success are M3 tertiary/secondary with no semantic meaning, so anchor the hue and let it tint; error is real
    readonly property color _warnAnchor: "#d4ad77"
    readonly property color _okAnchor:   "#94bd8b"
    readonly property color error:      _n ? "#dd92a2" : MatugenTheme.error
    readonly property color warning:    _n ? _warnAnchor : mix(_warnAnchor, MatugenTheme.warning, 0.30)
    readonly property color success:    _n ? _okAnchor   : mix(_okAnchor,   MatugenTheme.success, 0.30)

    function _lin(c: real): real {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }
    readonly property real _baseL: 903.3 * (0.2126 * _lin(background.r)
                                          + 0.7152 * _lin(background.g)
                                          + 0.0722 * _lin(background.b))
    readonly property real _elevK: Math.min(1.33, Math.max(1.0, 1.0 + 0.098 * (3.36 - _baseL)))

    readonly property real _lineK: ShellSettings.outlineStrength
    function lineAlpha(a: real): real { return Math.min(1, a * _lineK) }

    // borders and dividers are not text: they must not inherit the hierarchy sink _subtextBase
    // applies, or fixing text contrast quietly washes out every line in the shell
    readonly property color _lineBase: _hc ? subtext : (_n ? _pal.subtext : MatugenTheme.subtext)

    readonly property color outline: _hc ? withAlpha(text, lineAlpha(0.36))
                                        : _n ? withAlpha(_lineBase, lineAlpha(0.14))
                                             : withAlpha(mix(_lineBase, accent, 0.22), lineAlpha(0.17))

    readonly property color barSeparator: withAlpha(_n ? _lineBase : mix(_lineBase, accent, 0.10),
                                                    ShellSettings.dotOpacity)

    readonly property color panel: withAlpha(background,
        _hc ? Math.max(0.90, ShellSettings.barOpacity) : ShellSettings.barOpacity)
    readonly property color popup: background

    readonly property color menuPane:        _n ? mix(background, text, _elevK * (_hc ? 0.050 : 0.030))
                                                : mix(background, _hc ? text : surface, _elevK * (_hc ? 0.055 : 0.18))
    readonly property color menuCard:        _n ? mix(background, text, _elevK * (_hc ? 0.090 : 0.060))
                                                : mix(background, text, _elevK * (_hc ? 0.100 : 0.07))
    readonly property color menuCardBorder:  _hc ? withAlpha(text, lineAlpha(0.22))
                                                : _n ? withAlpha(_lineBase, lineAlpha(0.105))
                                                     : withAlpha(mix(_lineBase, accent, 0.22), lineAlpha(0.17))
    readonly property color menuDivider:     _hc ? withAlpha(text, lineAlpha(0.16))
                                                : _n ? withAlpha(_lineBase, lineAlpha(0.075))
                                                     : withAlpha(_lineBase, lineAlpha(0.085))
    readonly property color menuHover:       accent
    // wallpaper's card sits a step higher than neutral's, so its control needs a wider mix to hold
    // the same ~3 L* separation above the card that neutral gets from 0.060 -> 0.090
    readonly property color menuControl:     _n ? mix(background, text, _elevK * (_hc ? 0.125 : 0.090))
                                                : mix(background, text, _elevK * (_hc ? 0.130 : 0.100))
    readonly property color menuControlLine: _hc ? withAlpha(text, lineAlpha(0.24))
                                                : _n ? withAlpha(_lineBase, lineAlpha(0.115))
                                                     : withAlpha(_lineBase, lineAlpha(0.135))
    readonly property color menuControlLineHot: _hc ? withAlpha(accent, lineAlpha(0.45))
                                                   : _n ? withAlpha(_lineBase, lineAlpha(0.18))
                                                        : withAlpha(mix(_lineBase, accent, 0.18), lineAlpha(0.20))
    readonly property color menuTrack:       _hc ? withAlpha(text, 0.22)
                                                : _n ? withAlpha(_lineBase, 0.14)
                                                     : withAlpha(_lineBase, 0.16)
    readonly property color menuTextMuted:   mix(subtext, text, _hc ? 0.45 : (_n ? 0.30 : 0.24))
    readonly property color menuTextFaint:   mix(subtext, text, _hc ? 0.25 : (_n ? 0.15 : 0.10))

    // shared focus-ring weight: button-family controls (2px) vs embedded row/track indicators (1px)
    readonly property real focusRingAlpha:     0.72
    readonly property real focusRingSoftAlpha: 0.42

    readonly property int radiusPanel:   14
    readonly property int radiusCard:    12
    readonly property int radiusControl: 10
    // one step tighter than a control: nav and rail rows, inline wells, compact action buttons
    readonly property int radiusInline:   8
    readonly property int radiusField:    6
    readonly property int _surfaceRadiusTarget: ShellSettings.barFloating
        ? (ShellSettings.barCornerStyle === "flat" ? 0 : ShellSettings.barRadius)
        : radiusPanel
    property real surfaceRadius: _surfaceRadiusTarget
    MotionBehavior on surfaceRadius {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }

    readonly property int gapSection: 12

    function withAlpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function mix(base: color, tint: color, a: real): color {
        return Qt.rgba(
            base.r * (1 - a) + tint.r * a,
            base.g * (1 - a) + tint.g * a,
            base.b * (1 - a) + tint.b * a,
            1.0
        )
    }

    function rowFill(hovered: bool): color {
        return hovered ? mix(menuCard, text, 0.045 * _elevK) : menuCard
    }
}
