pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion
    readonly property real _s:  1.0

    function ms(base: int): int { return _rm ? 0 : Math.round(base / _s) }

    readonly property int instant: _rm ? 0 : Math.round(80  / _s)
    readonly property int fast:    _rm ? 0 : Math.round(120 / _s)
    readonly property int normal:  _rm ? 0 : Math.round(150 / _s)
    readonly property int medium:  _rm ? 0 : Math.round(170 / _s)
    readonly property int slow:    _rm ? 0 : Math.round(240 / _s)
    readonly property int width:   _rm ? 0 : Math.round(160 / _s)
    readonly property int color:   _rm ? 0 : Math.round(150 / _s)

    readonly property real popScaleFrom: 0.975
    readonly property real popEdgeOffset: 8
    readonly property int  popIn:      _rm ? 0 : Math.round(210 / _s)
    readonly property int  popInFade:  _rm ? 0 : Math.round(145 / _s)
    readonly property int  popOut:     _rm ? 0 : Math.round(145 / _s)
    readonly property int  popOutFade: _rm ? 0 : Math.round(120 / _s)
    readonly property int  popSettle:  _rm ? 0 : Math.round(210 / _s)

    readonly property int panelResize: _rm ? 0 : Math.round(240 / _s)
    readonly property int panelHeight: _rm ? 0 : Math.round(210 / _s)
    readonly property real panelVelocity: 1200 * _s
    readonly property int pageIn:      _rm ? 0 : Math.round(180 / _s)
    readonly property int pageOut:     _rm ? 0 : Math.round(110 / _s)
    readonly property real pageOffset: 8

    readonly property int barMorph: _rm ? 0 : Math.round(240 / _s)
}
