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

    // m3 emphasized-decelerate; the trailing 1,1 is the bezier end point qt requires
    readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1.0, 1, 1]

    readonly property real popScaleFrom: 0.975
    readonly property real popEdgeOffset: 8
    readonly property int  popIn:      _rm ? 0 : 210
    readonly property int  popInFade:  _rm ? 0 : 145
    readonly property int  popOut:     _rm ? 0 : 145
    readonly property int  popOutFade: _rm ? 0 : 120
    readonly property int  popSettle:  _rm ? 0 : 210

    // scroll physics are user-driven, not animation: they stay put under reduce-motion
    readonly property real flickDeceleration: 1800
    readonly property real flickVelocity:     2200

    // the largest moving surface in the shell: a pill's duration reads as a snap at this size
    readonly property int panelResize:   _rm ? 0 : 240
    readonly property int panelCollapse: _rm ? 0 : 115
    // quiet window a viewport must hold before scroll affordances trust it (see ScrollSettle)
    readonly property int panelSettle:   _rm ? 0 : 150
    readonly property real panelVelocity: 1200
    // never shorter than panelResize, or content lands opaque inside a still-resizing panel
    readonly property int pageIn:      _rm ? 0 : panelResize
    readonly property int pageOut:     _rm ? 0 : 110
    readonly property real pageOffset: 8

    readonly property int barMorph: _rm ? 0 : 240
}
