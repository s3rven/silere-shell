pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion

    function ms(base: int): int { return _rm ? 0 : base }

    // idle and reduce motion both mean "no visible motion"; taking both as arguments keeps it testable without a live idle state
    function allowsMotion(idle: bool, reduceMotion: bool): bool { return !idle && !reduceMotion }

    readonly property int instant: _rm ? 0 : 80
    readonly property int fast:    _rm ? 0 : 130
    readonly property int normal:  _rm ? 0 : 165
    readonly property int medium:  _rm ? 0 : 190
    readonly property int slow:    _rm ? 0 : 260
    readonly property int width:   _rm ? 0 : 180
    readonly property int color:   _rm ? 0 : 160
    // the whole shell recolours at once, so this is a scene change, not a state change
    readonly property int palette: _rm ? 0 : 420

    readonly property int hoverIn:  _rm ? 0 : 145
    readonly property int hoverOut: _rm ? 0 : 190
    readonly property int press:    _rm ? 0 : 90
    readonly property real hoverScale: 1.018
    readonly property real pressScale: 0.965

    // one tactile acknowledgement for the whole shell; surfaces vary the amplitude, never the timing
    readonly property int bumpRise:   _rm ? 0 : 70
    readonly property int bumpSettle: _rm ? 0 : 140

    // shared curves keep surfaces, content and shadows on the same velocity profile. The trailing 1,1 is the bezier end point Qt requires
    readonly property var standard:        [0.2, 0.0, 0.0, 1.0, 1, 1]
    readonly property var standardDecel:   [0.0, 0.0, 0.0, 1.0, 1, 1]
    readonly property var standardAccel:   [0.3, 0.0, 1.0, 1.0, 1, 1]
    // ease-out-cubic, not M3's emphasized decelerate: that curve opens at 14x linear velocity, which
    // spends half the travel in the first frame and crawls the rest. Nothing here moves far enough
    readonly property var emphasizedDecel: [0.215, 0.61, 0.355, 1.0, 1, 1]
    readonly property var emphasizedAccel: [0.3, 0.0, 0.8, 0.15, 1, 1]

    readonly property real popScaleFrom: 0.985
    // the card starts behind the bar and clears it inside the first frame, while it is still
    // near-transparent: travel shorter than the 8px popup gap reads as a twitch, not a drop
    readonly property real popEdgeOffset: 12
    readonly property int  popIn:      _rm ? 0 : 240
    // the compositor blurs these layers above an alpha threshold, so a slow fade holds the card
    // at part-alpha through the crossing; keep the reveal ahead of the travel
    readonly property int  popInFade:  _rm ? 0 : 160
    readonly property int  popOut:     _rm ? 0 : 150
    // the popup window unmaps on opacity, so the fade has to outlast the travel or the card
    // dissolves two thirds of the way through its own exit
    readonly property int  popOutFade: _rm ? 0 : 190
    readonly property int  popSettle:  _rm ? 0 : 240

    // scroll physics are user-driven, not animation: they stay put under reduce-motion
    readonly property real flickDeceleration: 1800
    readonly property real flickVelocity:     2200

    // the largest moving surface in the shell: a pill's duration reads as a snap at this size
    readonly property int panelResize:   _rm ? 0 : 240
    readonly property int panelCollapse: _rm ? 0 : 150
    // quiet window a viewport must hold before scroll affordances trust it (see ScrollSettle)
    readonly property int panelSettle:   _rm ? 0 : 180
    readonly property real panelVelocity: 1500
    // never shorter than panelResize, or content lands opaque inside a still-resizing panel
    readonly property int pageIn:      _rm ? 0 : panelResize
    readonly property int pageOut:     _rm ? 0 : 120
    readonly property real pageOffset: 10

    readonly property int barMorph: _rm ? 0 : 260
}
