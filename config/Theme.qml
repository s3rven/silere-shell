pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    id: root

    readonly property bool _n: ShellSettings.neutralTheme
    readonly property bool _hc: ShellSettings.highContrast
    // the one colour depth sinks toward; the theme preview mixes against it too
    readonly property color depthSink: "#000000"
    // matugen in light mode: dark ink on a light base. Whatever below assumes the opposite has to turn around
    readonly property bool _matugenLight: luminance(MatugenTheme.background) > luminance(MatugenTheme.text)
    readonly property bool paletteLight: !_n && _matugenLight

    readonly property var tones: ({
        black:    { background: "#030405", surface: "#121214", subtext: "#9296a1" },
        charcoal: { background: "#0b0c0e", surface: "#1b1b1c", subtext: "#9a9eaa" },
        graphite: { background: "#131315", surface: "#232324", subtext: "#a3a7b2" }
    })
    readonly property var _pal: tones[ShellSettings.baseTone] ?? tones.charcoal

    readonly property color _matuAccent: ShellSettings.matugenAccentRole === "secondary" ? MatugenTheme.success
                                       : ShellSettings.matugenAccentRole === "tertiary"  ? MatugenTheme.warning
                                       : MatugenTheme.accent

    // matugen's own base lands near the graphite tone; these sink it to charcoal and to black
    readonly property var depths: ({ none: 0.0, deep: 0.38, deeper: 0.80 })
    // sinking a light base under dark ink would leave nothing readable, so it keeps its own
    readonly property real _depthK: paletteLight ? 0.0 : (depths[ShellSettings.matugenDepth] ?? 0.0)
    // surface sinks slower than background, or the elevation separation flattens out
    readonly property color _matuBg:      mix(MatugenTheme.background, depthSink, _depthK)
    readonly property color _matuSurface: mix(MatugenTheme.surface,    depthSink, _depthK * 0.6)

    readonly property color _surfaceBase: _n ? _pal.surface   : _matuSurface
    readonly property color _textBase:    _n ? "#e9eaf0"      : MatugenTheme.text
    // on_surface_variant sits only 1.31:1 from on_surface, so secondary text reads as loud as
    // primary; sinking it toward the base restores the neutral palette's 2.2:1 split
    readonly property color _subtextBase: _n ? _pal.subtext
                                             : mix(MatugenTheme.subtext, _matuBg, paletteLight ? 0.10 : 0.25)

    readonly property color _tBackground: _n ? _pal.background : _matuBg
    readonly property color _tText:       _hc ? (paletteLight ? "#000000" : "#ffffff") : _textBase
    readonly property color _tSubtextSolid: _hc ? mix(_subtextBase, _tText, 0.32) : _subtextBase
    // the sink above is Silere's own, so it stops where a caption still reads: a palette made at
    // matugen's lowest contrast arrives near 4:1 and used to leave here under 3:1
    readonly property color _tSubtext:    popupOpacity < 1 ? root._glassInk(_tSubtextSolid, 3.0)
        : root.readableText(_tSubtextSolid, _glassWorst, 3.0)
    readonly property color _tSurface:    _hc ? mix(_surfaceBase, _tText, 0.035) : _surfaceBase

    // one eased source instead of one fade per call site: everything below is a plain
    // binding on these, so the shell recolours on a single curve and the local
    // ColorFades stand down for the duration (see ColorFade)
    property color background: root._tBackground
    property color text:       root._tText
    property color subtext:    root._tSubtext
    property color surface:    root._tSurface
    PaletteFade on background { gate: root._paletteReady }
    PaletteFade on text       { gate: root._paletteReady }
    PaletteFade on subtext    { gate: root._paletteReady }
    PaletteFade on surface    { gate: root._paletteReady }
    // the presets below are solved at this L*; matugen's dark primary lands near 80, so the
    // same hue reads hotter under Wallpaper than under Custom until it is walked back. A light
    // base needs it from the other side, where matugen's own primary sits near 40
    readonly property real _accentPresetL: paletteLight ? 42 : 70.8
    function balancedAccent(c: color): color {
        const l = lchOf(c)
        if (l.C < 4) return c
        return lchColor(_accentPresetL, Math.max(20, Math.min(38, l.C)), l.h)
    }
    // a light scheme's accent is dark, made for its light base; neutral's dark base has to walk it up
    function sourcedAccent(c: color): color {
        if (_n && _matugenLight) {
            const l = lchOf(c)
            return l.C < 4 ? lchColor(_accentPresetL, l.C, l.h) : balancedAccent(c)
        }
        return ShellSettings.matugenAccentBalance ? balancedAccent(c) : c
    }
    readonly property color wallpaperAccent: sourcedAccent(_matuAccent)
    readonly property color _tAccent: _n && !ShellSettings.neutralAccentAuto
        ? ShellSettings.neutralAccent : wallpaperAccent
    property color accent: root._tAccent
    PaletteFade on accent { gate: root._paletteReady }
    // the accent as a word or a glyph. Fills, rings, tracks and knobs keep the chosen accent; its ink holds a
    // caption's 3:1 over a white and a dark window on glass, or over the lightest control when opaque, where most
    // presets sat near 2.4:1 on a see-through menu. Solved on lightness alone, so the hue stays
    readonly property color _tAccentInk: root._captionInk(_tAccent)
    property color accentInk: root._tAccentInk
    PaletteFade on accentInk { gate: root._paletteReady }
    // a control's tint where it draws a word or a glyph: the theme's accent takes its ink, a status colour
    // already holds 3:1, and anything else is solved the same way
    function inkFor(c: color): color {
        if (Qt.colorEqual(c, root.accent)) return root.accentInk
        if (Qt.colorEqual(c, root.error) || Qt.colorEqual(c, root.warning) || Qt.colorEqual(c, root.success)) return c
        return root._captionInk(c)
    }
    // keep the chosen accent for fills, but lift very dark colours where the
    // bar uses them as small text, glyphs or the active workspace marker
    readonly property color _barDark: mix(Qt.rgba(0, 0, 0, 1), _tBackground, panelOpacity)
    readonly property color _barLight: mix(Qt.rgba(1, 1, 1, 1), _tBackground, panelOpacity)
    readonly property color _tBarAccent: root._readableAcross(_tAccent, _barDark, _barLight, _hc ? 7.0 : 4.5)
    property color barAccent: root._tBarAccent
    PaletteFade on barAccent { gate: root._paletteReady }
    // the same accent where it is a shape, not a word: the active workspace mark, a widget's glyph, a
    // level. At a label's 4.5:1 over a see-through bar only white is left of most hues; a mark needs 3:1
    readonly property color _tBarAccentMark: root._readableAcross(_tAccent, _barDark, _barLight, _barMarkMinimum)
    property color barAccentMark: root._tBarAccentMark
    PaletteFade on barAccentMark { gate: root._paletteReady }
    property color barText: root._readableAcross(_tText, _barDark, _barLight, _hc ? 7.0 : 4.5)
    property color barSubtext: root._readableAcross(_tSubtextSolid, _barDark, _barLight, _hc ? 7.0 : 3.0)
    PaletteFade on barText    { gate: root._paletteReady }
    PaletteFade on barSubtext { gate: root._paletteReady }
    // a status glyph on the bar: the menu's own red or amber is solved for a card, and over a pale
    // wallpaper behind a see-through bar it drops to 2:1. A glyph asks 3:1, not a label's 4.5
    readonly property real _barMarkMinimum: _hc ? 4.5 : 3.0
    property color barError:   root._readableAcross(_tErrorBase,   _barDark, _barLight, _barMarkMinimum)
    property color barWarning: root._readableAcross(_tWarningBase, _barDark, _barLight, _barMarkMinimum)
    property color barSuccess: root._readableAcross(_tSuccessBase, _barDark, _barLight, _barMarkMinimum)
    PaletteFade on barError   { gate: root._paletteReady }
    PaletteFade on barWarning { gate: root._paletteReady }
    PaletteFade on barSuccess { gate: root._paletteReady }
    // a colour handed to the bar from elsewhere, such as an alert's tint: as a mark, or as a word
    function barInk(c: color, label: bool): color {
        return root._readableAcross(c, _barDark, _barLight, label ? (_hc ? 7.0 : 4.5) : _barMarkMinimum)
    }
    readonly property color barHover: withAlpha(mix(barText, accent, 0.30), _hc ? 0.13 : 0.07)
    readonly property color barPressed: withAlpha(accent, _hc ? 0.26 : 0.18)
    readonly property color barSelected: withAlpha(accent, _hc ? 0.20 : 0.12)
    // read off the target, not the eased value: a lerp between opposite hues passes through low chroma, and this must not flicker on the way
    readonly property bool accentColorless: lchOf(_tAccent).C < 4
    // matugen warning/success are M3 tertiary/secondary with no semantic meaning, so anchor the hue and let it tint; error is real
    readonly property color _warnAnchor: "#d4ad77"
    readonly property color _okAnchor:   "#94bd8b"
    readonly property color _errorSource:   _n ? Qt.color("#dd92a2") : MatugenTheme.error
    readonly property color _warningSource: _n ? _warnAnchor : _semanticInk(_warnAnchor, MatugenTheme.warning)
    readonly property color _successSource: _n ? _okAnchor   : _semanticInk(_okAnchor,   MatugenTheme.success)
    readonly property color _tErrorBase:   root._apartFromAccent(_errorSource, [_warningSource, _successSource])
    readonly property color _tWarningBase: root._apartFromAccent(_warningSource, [_tErrorBase, _successSource])
    readonly property color _tSuccessBase: root._apartFromAccent(_successSource, [_tErrorBase, _tWarningBase])
    // a status colour must not pass for the accent: Gold drew warnings, Leaf successes and Coral errors in the accent's
    // own colour (CIEDE2000 2.0, 2.8, 5.6), and so did an auto accent off an amber, green or red wallpaper, so an urgent
    // workspace read as the active one. The gap is taken on the a*b* plane, which the bar's lightness solve leaves alone.
    // Only the hue turns, the least that clears the accent and the other status colours, so L* (and contrast) and
    // chroma hold; turning away from the accent alone walked a red wallpaper's error onto its warning
    readonly property real _statusGap: 18
    function _apartFromAccent(status: color, others: var): color {
        const lab = c => _labOf(c)
        const accent = lab(_tAccent)
        const gap = (x, y) => Math.hypot(x.a - y.a, x.b - y.b)
        if (gap(lab(status), accent) >= _statusGap) return status
        const own = lchOf(status)
        const away = ((own.h - lchOf(_tAccent).h) % 360 + 540) % 360 - 180 >= 0 ? 1 : -1
        const kept = others.map(lab)
        const worstOf = l => Math.min(gap(l, accent), ...kept.map(k => gap(l, k)))
        // where nothing clears every colour, the least crowded turn wins, and not turning at all is one of them
        let best = status, bestGap = worstOf(lab(status))
        for (let step = 1; step <= 12; step++) for (const turn of [away, -away]) {
            const out = lchColor(own.L, own.C, own.h + turn * 5 * step)
            const worst = worstOf(lab(out))
            if (worst >= _statusGap) return out
            if (worst > bestGap) { best = out; bestGap = worst }
        }
        return best
    }
    // a status colour is read as a glyph or a short word on a card; over glass it has to hold
    // through a white window behind a dark menu and a dark one behind a light menu
    readonly property color _tError:    root._glassInk(_tErrorBase,   3.0)
    readonly property color _tWarning:  root._glassInk(_tWarningBase, 3.0)
    readonly property color _tSuccess:  root._glassInk(_tSuccessBase, 3.0)
    // both anchors are pale, which only reads on a dark base
    function _semanticInk(anchor: color, tint: color): color {
        const ink = tintKeepingChroma(anchor, tint, 0.30)
        return paletteLight ? readableText(ink, mix(_tBackground, _tText, _controlK), 4.5) : ink
    }
    property color error:   root._tError
    property color warning: root._tWarning
    property color success: root._tSuccess
    PaletteFade on error   { gate: root._paletteReady }
    PaletteFade on warning { gate: root._paletteReady }
    PaletteFade on success { gate: root._paletteReady }

    // the wallpaper palette lands a moment after the shell does; easing in from the bundled colours on every launch would read as a flash, not a transition
    property bool _paletteReady: false
    Timer { interval: 700; running: true; onTriggered: root._paletteReady = true }

    readonly property string paletteSignature: "" + _tBackground + _tSurface + _tText
        + _tSubtext + _tAccent + _tError + _tWarning + _tSuccess + _tLineBase
        + _tMenuTextDetail + _tMenuTextWarning + _tMenuTextQuiet + _tAccentInk
    // high contrast and the colour source flip the formulas themselves, not only the colours they read, and that flip has no
    // fade of its own: the local fades carry it, or a switch's knob went from the accent to dark grey in one frame
    readonly property bool paletteShifting: _shiftWindow.running && !_modeWindow.running
    onPaletteSignatureChanged: {
        if (!root._paletteReady
                || !Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)) return
        _shiftWindow.restart()
    }
    Timer { id: _shiftWindow; interval: Motion.palette }
    on_HcChanged: _modeWindow.restart()
    on_NChanged: _modeWindow.restart()
    Timer { id: _modeWindow; interval: Motion.palette }

    // solved at L* 70.8, C* 20-36: equal visual weight on all three dark bases
    readonly property var neutralAccentPresets: [
        { color: "#8db2d0", name: "Glacier" },
        { color: "#52b8e8", name: "Sky"     },
        { color: "#9babe9", name: "Iris"    },
        { color: "#c99fd3", name: "Orchid"  },
        { color: "#56bdb6", name: "Aqua"    },
        { color: "#86ba8b", name: "Leaf"    },
        { color: "#eb979a", name: "Coral"   },
        { color: "#cca870", name: "Gold"    }
    ]

    function _lin(c: real): real {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }
    readonly property real _baseL: _labOf(background).L
    function _elevationForLightness(lightness: real): real {
        return Math.min(1.33, Math.max(1.0, 1.0 + 0.098 * (3.36 - lightness)))
    }
    readonly property real _elevK: root._elevationForLightness(_baseL)

    readonly property real _lineK: ShellSettings.outlineStrength
    function lineAlpha(a: real): real { return Math.min(1, a * _lineK) }

    // borders and dividers are not text: they must not inherit the hierarchy sink _subtextBase
    // applies, or fixing text contrast quietly washes out every line in the shell
    readonly property color _tLineBase: _hc ? _tSubtextSolid : (_n ? _pal.subtext : MatugenTheme.subtext)
    property color _lineBase: root._tLineBase
    PaletteFade on _lineBase { gate: root._paletteReady }

    // high contrast and the colour source reshape a line, and a palette shift never eases that: the lines most outlines
    // draw ride an eased blend of both forms instead, so a switch fades them with the rest. Both forms only gain
    // lightness and alpha toward high contrast, so the blend never passes through a brighter grey
    property real _hcK: _hc ? 1 : 0
    property real _nK: _n ? 1 : 0
    MotionBehavior on _hcK { gate: root._paletteReady
        NumberAnimation { duration: Motion.palette; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel } }
    MotionBehavior on _nK { gate: root._paletteReady
        NumberAnimation { duration: Motion.palette; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel } }
    function _lerp(a: color, b: color, k: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
    }
    function _modeLine(wallpaper: color, neutral: color, contrast: color): color {
        return root._lerp(root._lerp(wallpaper, neutral, _nK), contrast, _hcK)
    }

    readonly property color outline: root._modeLine(withAlpha(mix(_lineBase, accent, 0.22), lineAlpha(0.17)),
        withAlpha(_lineBase, lineAlpha(0.14)), withAlpha(text, lineAlpha(0.36)))

    readonly property color barSeparator: withAlpha(_n ? _lineBase : mix(_lineBase, accent, 0.10), 0.38)

    // signature, not structure: keeps its accent in neutral where the panel lines drop theirs
    readonly property color barLine: mix(_lineBase, accent, 0.30)

    // high contrast floors this, so the readout has to report the effective value, not the setting
    readonly property real panelOpacity: _hc ? Math.max(0.90, ShellSettings.barOpacity)
                                             : ShellSettings.barOpacity
    readonly property color panel: withAlpha(background, panelOpacity)
    // what floats over windows stays see-through only while blur frosts it: unblurred, the text under
    // a popup reads as sharply as the popup's own. The bar sits over the wallpaper and keeps its setting
    readonly property bool frosted: ShellSettings.surfaceBlur && Compositor.blurBlocker.length === 0
    // popups follow a translucent bar only down to where a label still reads with a white window behind it
    readonly property real glassFloor: root._solveGlassFloor(_tBackground, _tText, 4.5)
    readonly property real popupOpacity: ShellSettings.popupMatchBarOpacity && frosted
        ? Math.max(panelOpacity, glassFloor) : 1
    readonly property color popup: withAlpha(background, popupOpacity)
    // the lightest glass layer, a control, over the backdrop furthest from the base: what text on glass has to survive
    function _controlOverBackdrop(base: color, ink: color, alpha: real, backdrop: color): color {
        return mix(mix(backdrop, base, alpha), ink,
            root._elevationForLightness(_labOf(base).L) * _controlMix)
    }
    function _controlOverWorst(base: color, ink: color, alpha: real): color {
        return root._controlOverBackdrop(base, ink, alpha,
            paletteLight ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1))
    }
    readonly property color _glassWorst: root._controlOverWorst(_tBackground, _tText, popupOpacity)
    readonly property color _glassDark: root._controlOverBackdrop(_tBackground, _tText,
        popupOpacity, Qt.rgba(0, 0, 0, 1))
    readonly property color _glassLight: root._controlOverBackdrop(_tBackground, _tText,
        popupOpacity, Qt.rgba(1, 1, 1, 1))
    // ink on a see-through popup. Solved against the worst backdrop alone, the stronger of white
    // and black can be the wrong one: white text puts that backdrop at mid grey, where black
    // out-contrasts white by a hair, and a dark menu's captions turned black over a dark window
    function _glassInk(ink: color, minimum: real): color {
        return popupOpacity < 1 ? root._readableAcross(ink, _glassLight, _glassDark, minimum) : ink
    }
    function _solveGlassFloor(base: color, ink: color, minimum: real): real {
        let low = 0, high = 1
        for (let i = 0; i < 10; i++) {
            const middle = (low + high) / 2
            if (root.contrastRatio(ink, root._controlOverWorst(base, ink, middle)) >= minimum) high = middle
            else low = middle
        }
        return Math.ceil(high * 100) / 100
    }

    // when popups match a translucent bar the menu turns to glass with them: its pane, cards and controls
    // become tints over the one translucent fill, so the blur reads through every layer instead of
    // stopping at solid slabs. Each tint is the opaque step it replaces, taken over the layer below
    // latched behind the shift window: a colour fade from an opaque slab to a see-through tint
    // passes through a half-opaque grey, which flashed every faded control on a blur toggle
    readonly property bool _glassWanted: popup.a < 1
    property bool glass: false
    Component.onCompleted: root.glass = root._glassWanted
    on_GlassWantedChanged: {
        // a slab turning to glass still snaps, mode switch or not
        _modeWindow.stop()
        _shiftWindow.restart()
        root.glass = root._glassWanted
    }
    function _over(total: real, under: real): real { return 1 - (1 - total) / (1 - under) }
    readonly property real _paneK: _elevK * (_n ? (_hc ? 0.050 : 0.030) : (_hc ? 0.055 : 0.020))
    readonly property real _cardK: _elevK * (_n ? (_hc ? 0.090 : 0.060) : (_hc ? 0.100 : 0.070))
    readonly property real _controlMix: _n ? (_hc ? 0.125 : 0.090) : (_hc ? 0.130 : 0.100)
    readonly property real _controlK: _elevK * _controlMix

    readonly property color menuPane:        glass
        ? (_n || _hc ? withAlpha(text, _paneK) : withAlpha(surface, _elevK * 0.18))
        : _n ? mix(background, text, _elevK * (_hc ? 0.050 : 0.030))
             : mix(background, _hc ? text : surface, _elevK * (_hc ? 0.055 : 0.18))
    readonly property color menuCard:        glass ? withAlpha(text, _over(_cardK, _paneK)) : menuCardSolid
    // for what floats over content, like a hover label, and must not let the content show through
    readonly property color menuCardSolid:   _n ? mix(background, text, _elevK * (_hc ? 0.090 : 0.060))
                                                : mix(background, text, _elevK * (_hc ? 0.100 : 0.07))
    readonly property color menuCardBorder:  root._modeLine(withAlpha(mix(_lineBase, accent, 0.22), lineAlpha(0.17)),
        withAlpha(_lineBase, lineAlpha(0.105)), withAlpha(text, lineAlpha(0.22)))
    readonly property color menuDivider:     _hc ? withAlpha(text, lineAlpha(0.16))
                                                : _n ? withAlpha(_lineBase, lineAlpha(0.075))
                                                     : withAlpha(_lineBase, lineAlpha(0.085))
    readonly property color menuHover:       accent
    // wallpaper's card sits a step higher than neutral's, so its control needs a wider mix to hold
    // the same ~3 L* separation above the card that neutral gets from 0.060 -> 0.090
    readonly property color menuControl:     glass ? withAlpha(text, _over(_controlK, _cardK)) : menuControlSolid
    readonly property color menuControlSolid: mix(background, text, _controlK)
    readonly property color menuControlLine: root._modeLine(withAlpha(_lineBase, lineAlpha(0.135)),
        withAlpha(_lineBase, lineAlpha(0.115)), withAlpha(text, lineAlpha(0.24)))
    readonly property color menuControlLineHot: _hc ? withAlpha(accent, lineAlpha(0.45))
                                                   : _n ? withAlpha(_lineBase, lineAlpha(0.18))
                                                        : withAlpha(mix(_lineBase, accent, 0.18), lineAlpha(0.20))
    // selection has to out-weigh the accent hover line, or under high contrast the chip
    // being hovered reads as the chosen one. Takes the caller's accent, not the theme's
    function controlLineActive(c: color): color { return withAlpha(c, lineAlpha(_hc ? 0.60 : 0.32)) }
    readonly property color menuTrack:       _hc ? withAlpha(text, 0.22)
                                                : _n ? withAlpha(_lineBase, 0.14)
                                                     : withAlpha(_lineBase, 0.16)
    // not lineAlpha: the base swatches sit within 1 L* of their card, so this edge is what
    // makes them countable at all and must survive outline strength being turned down
    readonly property color swatchEdge:      withAlpha(text, 0.20 + 0.14 * _hcK)
    readonly property color menuTextMuted:   mix(subtext, text, _hc ? 0.45 : (_n ? 0.30 : 0.24))
    readonly property color menuTextFaint:   mix(subtext, text, _hc ? 0.25 : (_n ? 0.15 : 0.10))
    // solved on the target palette and faded, not re-solved every frame; glass asks less, or detail outshines labels
    readonly property real _detailMinimum: popupOpacity < 1 ? 3.0 : 4.5
    readonly property color _tMenuTextDetail: root._detailInk(
        withAlpha(_tSubtext, _hc ? 1.0 : 0.85))
    readonly property color _tMenuTextWarning: root._detailInk(
        withAlpha(mix(_tSubtext, _tWarning, 0.30), _hc ? 1.0 : 0.85))
    function _detailInk(ink: color): color {
        return popupOpacity < 1 ? root._glassInk(ink, _detailMinimum)
            : root.readableText(ink, _glassWorst, _detailMinimum)
    }
    property color menuTextDetail: _tMenuTextDetail
    // the quiet caption: hints, counts, a card's meta, a thread's earlier lines. Fainter than a detail, still 3:1. Alpha on
    // subtext, applied after any solve, took these to 2:1 on a light popup over a dark window, and no ink half made of its
    // backdrop reaches 3:1 there, so the tone is mixed opaque toward the base first, then solved over either backdrop
    // On glass a mid tone cannot read over both a white and a black window, so the solve lands at an extreme; it is
    // capped at the detail tone, never louder than the descriptions it sits among. An opaque panel keeps the quiet tone
    readonly property color _tMenuTextQuiet: root._quietInk(mix(_tBackground, _tSubtext, _hc ? 0.85 : 0.54),
        _tMenuTextDetail)
    function _quietInk(nominal: color, cap: color): color {
        const solved = root._captionInk(nominal)
        return root.contrastRatio(solved, _tBackground) > root.contrastRatio(cap, _tBackground) ? cap : solved
    }
    function _captionInk(ink: color): color {
        return popupOpacity < 1 ? root._glassInk(ink, 3.0) : root.readableText(ink, _glassWorst, 3.0)
    }
    property color menuTextQuiet: _tMenuTextQuiet
    property color menuTextWarning: _tMenuTextWarning
    PaletteFade on menuTextDetail  { gate: root._paletteReady }
    PaletteFade on menuTextQuiet   { gate: root._paletteReady }
    PaletteFade on menuTextWarning { gate: root._paletteReady }

    function luminance(c: color): real {
        return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)
    }

    // background must be opaque: over glass the real contrast depends on the desktop
    function contrastRatio(foreground: color, background: color): real {
        const front = root.luminance(mix(background, foreground, foreground.a))
        const back = root.luminance(background)
        return (Math.max(front, back) + 0.05) / (Math.min(front, back) + 0.05)
    }

    // contrast is bought with lightness alone. Blending toward white in srgb greys a colour on the
    // way: at the 4.5:1 a see-through bar asks, a wallpaper accent arrived as an off-white. Walking
    // L* holds the hue and whatever chroma the gamut still has at that lightness
    function _solveInk(foreground: color, lighter: bool, passes: var): color {
        const l = lchOf(foreground)
        const span = (lighter ? 100 : 0) - l.L
        const alpha = foreground.a
        const tinted = t => {
            const out = lchColor(l.L + span * t, l.C, l.h)
            return Qt.rgba(out.r, out.g, out.b, alpha)
        }
        // contrast reads luminance, and an opaque ink's luminance is its L* whatever chroma it keeps:
        // search on a grey of each lightness and fit the hue into the gamut once, at the end
        const probe = alpha >= 1 ? (t => _labColor(l.L + span * t, 0, 0)) : tinted
        let low = 0, high = 1
        for (let i = 0; i < 10; i++) {
            const middle = (low + high) / 2
            if (passes(probe(middle))) high = middle
            else low = middle
        }
        let out = tinted(high)
        // _labFits lets a channel sit 0.0005 past the gamut and _labColor clamps it back, so the fitted
        // colour's luminance lands a hair off the grey's
        for (let i = 0; i < 8 && high < 1 && !passes(out); i++) {
            high = Math.min(1, high + 1 / 512)
            out = tinted(high)
        }
        return out
    }

    function readableText(foreground: color, background: color, minimum: real): color {
        if (root.contrastRatio(foreground, background) >= minimum) return foreground
        const white = Qt.rgba(1, 1, 1, 1), black = Qt.rgba(0, 0, 0, 1)
        const lighter = root.contrastRatio(white, background) >= root.contrastRatio(black, background)
        return root._solveInk(foreground, lighter, ink => root.contrastRatio(ink, background) >= minimum)
    }

    // a knob over glass has to survive both a dark wallpaper and a white window.
    // Choosing the strongest ink on just one can make it vanish over the other
    function _readableAcross(foreground: color, first: color, second: color, minimum: real): color {
        function contrast(ink) {
            return Math.min(root.contrastRatio(ink, first), root.contrastRatio(ink, second))
        }
        if (contrast(foreground) >= minimum) return foreground
        const white = Qt.rgba(1, 1, 1, 1), black = Qt.rgba(0, 0, 0, 1)
        return root._solveInk(foreground, contrast(white) >= contrast(black), ink => contrast(ink) >= minimum)
    }

    // shared focus-ring weight: button-family controls (2px) vs embedded row/track indicators (1px)
    // high contrast re-bases every other line onto white text; the ring keeps its accent, so it buys the contrast in alpha
    readonly property real focusRingAlpha:     _hc ? 0.92 : 0.72
    readonly property real focusRingSoftAlpha: _hc ? 0.72 : 0.42

    // one disabled depth for every control; high contrast lifts it so a dimmed row stays readable
    readonly property real disabledOpacity: _hc ? 0.62 : 0.45

    function buttonFill(c: color, hovered: bool, pressed: bool): color {
        if (pressed) return withAlpha(c, _hc ? 0.20 : 0.13)
        if (hovered) return withAlpha(mix(text, c, 0.24), _hc ? 0.12 : 0.075)
        return withAlpha(text, _hc ? 0.060 : 0.035)
    }
    function buttonLine(c: color, hovered: bool, pressed: bool): color {
        if (pressed) return withAlpha(c, lineAlpha(_hc ? 0.54 : 0.34))
        if (hovered) return withAlpha(c, lineAlpha(_hc ? 0.42 : 0.24))
        return menuControlLine
    }
    function emphasisButtonFill(c: color, hovered: bool, pressed: bool): color {
        if (_hc) return blend(menuControl, c, pressed ? 0.54 : hovered ? 0.48 : 0.42)
        return blend(menuControl, c, pressed ? 0.40 : hovered ? 0.34 : 0.28)
    }

    function controlTrackFill(c: color, active: bool,
                              hovered: bool, pressed: bool): color {
        if (active) {
            const k = _hc
                ? (_n ? (pressed ? 0.80 : hovered ? 0.74 : 0.68)
                      : (pressed ? 0.85 : hovered ? 0.79 : 0.73))
                : (_n ? (pressed ? 0.60 : hovered ? 0.54 : 0.48)
                      : (pressed ? 0.64 : hovered ? 0.58 : 0.52))
            return blend(menuControl, c, k)
        }
        return blend(menuControl, text,
            pressed ? 0.14 : hovered ? 0.085 : 0.035)
    }
    function controlTrackLine(c: color, active: bool,
                              hovered: bool, pressed: bool): color {
        if (active) return withAlpha(c, lineAlpha(
            pressed ? (_hc ? 0.72 : 0.52)
                : hovered ? (_hc ? 0.60 : 0.40)
                : (_hc ? 0.44 : 0.26)))
        if (pressed) return withAlpha(c, lineAlpha(_hc ? 0.50 : 0.30))
        return hovered ? menuControlLineHot : menuControlLine
    }
    // a switch is read at a glance, not aimed at, so its track sits far deeper than a
    // slider's fill; that is the room the accent knob needs to stay legible on top of it
    function _switchTrackMix(hovered: bool, pressed: bool): real {
        return _hc ? (pressed ? 0.85 : hovered ? 0.79 : 0.73)
            : (pressed ? 0.32 : hovered ? 0.27 : 0.22)
    }
    function switchTrackFill(c: color, checked: bool,
                             hovered: bool, pressed: bool): color {
        if (checked) return blend(menuControl, c, root._switchTrackMix(hovered, pressed))
        return blend(menuControl, text, pressed ? 0.14 : hovered ? 0.085 : 0.035)
    }

    // a slider knob rides its own filled track, so it reads as the accent with a lift; the
    // toggle knob below stays near-text because it has to carry against a full accent track
    function sliderKnobFill(c: color, hovered: bool, pressed: bool): color {
        if (_hc) return mix(text, c, pressed ? 0.13 : hovered ? 0.09 : 0.055)
        return mix(c, text, pressed ? 0.30 : hovered ? 0.24 : 0.18)
    }

    // keep the accent where it reads against the track; extreme colours need
    // a lighter or darker knob that also survives the backdrop behind glass
    function controlKnobFill(c: color, active: bool,
                             hovered: bool, pressed: bool): color {
        if (active) {
            const preferred = _hc ? mix(text, c, pressed ? 0.13 : hovered ? 0.09 : 0.055)
                : mix(c, text, pressed ? 0.22 : hovered ? 0.12 : 0.0)
            const track = mix(glass ? _glassWorst : menuControlSolid, c,
                root._switchTrackMix(hovered, pressed))
            return glass ? root._readableAcross(preferred, track,
                mix(_glassDark, c, root._switchTrackMix(hovered, pressed)), 3.0)
                : root.readableText(preferred, track, 3.0)
        }
        if (_hc) {
            return mix(subtext, text, pressed ? 0.28 : hovered ? 0.23 : 0.18)
        }
        const k = pressed ? 0.42 : hovered ? 0.36 : 0.30
        // a tint over glass: a fixed grey matches its track once the wallpaper behind is mid-light and vanishes
        return glass ? withAlpha(text, k) : mix(menuControlSolid, text, k)
    }

    readonly property int radiusPanel:   14
    // the inner steps follow Roundness in proportion, so Flat squares the cards inside a square menu
    // instead of leaving them round; the stock 14 keeps the steps below exactly
    function _rounded(base: int): int { return Math.round(base * _surfaceRadiusTarget / radiusPanel) }
    readonly property int radiusCard:    _rounded(12)
    readonly property int radiusControl: _rounded(10)
    // one step tighter than a control: nav and rail rows, inline wells, compact action buttons
    readonly property int radiusInline:  _rounded(8)
    readonly property int radiusField:   _rounded(6)
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

    // mix() for colours that may be translucent: weighs each by its own alpha and keeps the result's,
    // so a tint over glass stays a tint. Identical to mix() when both are opaque
    function blend(base: color, tint: color, a: real): color {
        const wb = base.a * (1 - a)
        const wt = tint.a * a
        const out = wb + wt
        if (out <= 0) return Qt.rgba(0, 0, 0, 0)
        return Qt.rgba((base.r * wb + tint.r * wt) / out, (base.g * wb + tint.g * wt) / out,
            (base.b * wb + tint.b * wt) / out, out)
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

    function rowFill(hovered: bool, pressed: bool): color {
        return pressed ? blend(menuCard, accent, 0.085 * _elevK)
            : hovered ? blend(menuCard, text, 0.045 * _elevK) : menuCard
    }
}
