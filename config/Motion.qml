pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion

    function ms(base: int): int { return _rm ? 0 : base }

    readonly property int instant: _rm ? 0 : 80
    readonly property int fast:    _rm ? 0 : 120
    readonly property int normal:  _rm ? 0 : 150
    readonly property int medium:  _rm ? 0 : 170
    readonly property int slow:    _rm ? 0 : 240
    readonly property int width:   _rm ? 0 : 160
    readonly property int color:   _rm ? 0 : 150

    readonly property real popScaleFrom: 0.975
    readonly property real popEdgeOffset: 8
    readonly property int  popIn:      _rm ? 0 : 210
    readonly property int  popInFade:  _rm ? 0 : 145
    readonly property int  popOut:     _rm ? 0 : 145
    readonly property int  popOutFade: _rm ? 0 : 120
    readonly property int  popSettle:  _rm ? 0 : 210

    readonly property int panelResize:   _rm ? 0 : 165
    readonly property int panelCollapse: _rm ? 0 : 115
    // quiet window a viewport must hold before scroll affordances trust it (see ScrollSettle)
    readonly property int panelSettle:   _rm ? 0 : 150
    readonly property real panelVelocity: 1200
    readonly property int pageIn:      _rm ? 0 : 180
    readonly property int pageOut:     _rm ? 0 : 110
    readonly property real pageOffset: 8

    readonly property int barMorph: _rm ? 0 : 240
}
