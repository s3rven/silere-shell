pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion
    readonly property real _s:  Math.max(0.1, ShellSettings.animSpeed)

    // For one-off durations that don't fit a token: honours reduceMotion and
    // animSpeed the same way the tokens do.
    function ms(base: int): int { return _rm ? 0 : Math.round(base / _s) }

    readonly property int instant: _rm ? 0 : Math.round(80  / _s)
    readonly property int fast:    _rm ? 0 : Math.round(120 / _s)
    readonly property int normal:  _rm ? 0 : Math.round(150 / _s)
    readonly property int medium:  _rm ? 0 : Math.round(200 / _s)
    readonly property int slow:    _rm ? 0 : Math.round(300 / _s)
    readonly property int width:   _rm ? 0 : Math.round(180 / _s)
    readonly property int color:   _rm ? 0 : Math.round(150 / _s)
}
