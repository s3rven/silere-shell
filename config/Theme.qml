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
    readonly property color warning:    _n ? _warnAnchor : tintKeepingChroma(_warnAnchor, MatugenTheme.warning, 0.30)
    readonly property color success:    _n ? _okAnchor   : tintKeepingChroma(_okAnchor,   MatugenTheme.success, 0.30)

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
    // the popup layers carry no compositor blur, so this stays opt-in and off by default
    readonly property color popup: ShellSettings.popupMatchBarOpacity ? panel : background

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
    // selection has to out-weigh the accent hover line, or under high contrast the chip
    // being hovered reads as the chosen one. Takes the caller's accent, not the theme's.
    function controlLineActive(c: color): color { return withAlpha(c, lineAlpha(_hc ? 0.60 : 0.32)) }
    readonly property color menuTrack:       _hc ? withAlpha(text, 0.22)
                                                : _n ? withAlpha(_lineBase, 0.14)
                                                     : withAlpha(_lineBase, 0.16)
    readonly property color menuTextMuted:   mix(subtext, text, _hc ? 0.45 : (_n ? 0.30 : 0.24))
    readonly property color menuTextFaint:   mix(subtext, text, _hc ? 0.25 : (_n ? 0.15 : 0.10))
    // row descriptions and hints: 10px type against a near-black card, so the sink that
    // keeps secondary text under its label has a floor. high contrast lifts it through subtext
    readonly property color menuTextDetail:  withAlpha(subtext, 0.70)

    // shared focus-ring weight: button-family controls (2px) vs embedded row/track indicators (1px)
    // high contrast re-bases every other line onto white text; the ring keeps its accent, so it buys the contrast in alpha
    readonly property real focusRingAlpha:     _hc ? 0.92 : 0.72
    readonly property real focusRingSoftAlpha: _hc ? 0.72 : 0.42

    readonly property int radiusPanel:   14
    readonly property int radiusCard:    12
    readonly property int radiusControl: 10
    // one step tighter than a control: nav and rail rows, inline wells, compact action buttons
    readonly property int radiusInline:   8
    readonly property int radiusField:    6
    readonly property int _surfaceRadiusTarget: ShellSettings.barFloating
        ? ShellSettings.barRadius
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

    function _unlin(c: real): real {
        return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055
    }

    function _labOf(c: color): var {
        const r = _lin(c.r), g = _lin(c.g), b = _lin(c.b)
        const f = t => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116
        const fx = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
        const fy = f(0.2126 * r + 0.7152 * g + 0.0722 * b)
        const fz = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
        return { L: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz) }
    }

    function _labColor(L: real, a: real, b: real): color {
        const fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        const g = t => { const c = t * t * t; return c > 0.008856 ? c : (t - 16 / 116) / 7.787 }
        const X = g(fx) * 0.95047, Y = g(fy), Z = g(fz) * 1.08883
        const ch = v => Math.max(0, Math.min(1, _unlin(Math.max(0, Math.min(1, v)))))
        return Qt.rgba(ch( 3.2406 * X - 1.5372 * Y - 0.4986 * Z),
                       ch(-0.9689 * X + 1.8758 * Y + 0.0415 * Z),
                       ch( 0.0557 * X - 0.2040 * Y + 1.0570 * Z), 1.0)
    }

    function lchOf(c: color): var {
        const l = _labOf(c)
        return { L: l.L, C: Math.sqrt(l.a * l.a + l.b * l.b),
                 h: (Math.atan2(l.b, l.a) * 180 / Math.PI + 360) % 360 }
    }

    // linear rgb in range is equivalent to srgb in range, so test before the transfer curve
    function _labFits(L: real, a: real, b: real): bool {
        const fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        const g = t => { const c = t * t * t; return c > 0.008856 ? c : (t - 16 / 116) / 7.787 }
        const X = g(fx) * 0.95047, Y = g(fy), Z = g(fz) * 1.08883
        const ok = v => v >= -0.0005 && v <= 1.0005
        return ok( 3.2406 * X - 1.5372 * Y - 0.4986 * Z)
            && ok(-0.9689 * X + 1.8758 * Y + 0.0415 * Z)
            && ok( 0.0557 * X - 0.2040 * Y + 1.0570 * Z)
    }

    // hold L* and hue, walk chroma down to the gamut edge: clamping rgb instead would shift the hue
    function lchColor(L: real, C: real, h: real): color {
        const r = h * Math.PI / 180, cos = Math.cos(r), sin = Math.sin(r)
        let lo = 0, hi = Math.max(0, C)
        if (_labFits(L, hi * cos, hi * sin)) return _labColor(L, hi * cos, hi * sin)
        for (let i = 0; i < 12; i++) {
            const mid = (lo + hi) / 2
            if (_labFits(L, mid * cos, mid * sin)) lo = mid
            else hi = mid
        }
        return _labColor(L, lo * cos, lo * sin)
    }

    // an srgb lerp between distant hues cancels chroma, so put the anchor's chroma back after
    function tintKeepingChroma(anchor: color, tint: color, a: real): color {
        const blended = mix(anchor, tint, a)
        const m = _labOf(blended), src = _labOf(anchor)
        const cm = Math.sqrt(m.a * m.a + m.b * m.b)
        if (cm < 0.0001) return blended
        const k = Math.sqrt(src.a * src.a + src.b * src.b) / cm
        return _labColor(m.L, m.a * k, m.b * k)
    }

    function rowFill(hovered: bool): color {
        return hovered ? mix(menuCard, text, 0.045 * _elevK) : menuCard
    }
}
