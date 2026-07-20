pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion
    readonly property real _s:  1.0

    // For one-off durations that don't fit a token: honours reduceMotion the same way the tokens do.
    function ms(base: int): int { return _rm ? 0 : Math.round(base / _s) }

    readonly property int instant: _rm ? 0 : Math.round(80  / _s)
    readonly property int fast:    _rm ? 0 : Math.round(120 / _s)
    readonly property int normal:  _rm ? 0 : Math.round(150 / _s)
    readonly property int medium:  _rm ? 0 : Math.round(170 / _s)
    readonly property int slow:    _rm ? 0 : Math.round(240 / _s)
    readonly property int width:   _rm ? 0 : Math.round(160 / _s)
    readonly property int color:   _rm ? 0 : Math.round(150 / _s)

    // shared open/close tokens for all bar-anchored popups (menu, calendar, tray)
    // pure fade: no scale (1.0) and no edge slide, so popups don't appear to move
    readonly property real popScaleFrom: 1.0
    readonly property int  popIn:      _rm ? 0 : Math.round(165 / _s)
    readonly property int  popInFade:  _rm ? 0 : Math.round(150 / _s)
    readonly property int  popOut:     _rm ? 0 : Math.round(115 / _s)
    readonly property int  popOutFade: _rm ? 0 : Math.round(110 / _s)
    readonly property int  popSettle:  _rm ? 40 : Math.max(40, Math.round(185 / _s))
}
