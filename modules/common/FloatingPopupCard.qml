pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// shared placement + open/close choreography for bar-edge popups (calendar, tray).
// trigger-proportional x: anchor keeps its relative screen position, so a centre click centres and an edge click hugs that side (no edge saturation on a custom-width bar).
Rectangle {
    id: root

    required property var win
    required property bool open
    required property real anchorX
    required property bool barBottom

    property bool _placementSettled: false
    readonly property real _originX: Math.max(0, Math.min(width, anchorX - x))

    readonly property int  _barInset: ShellSettings.barFloating ? 4 : 0
    readonly property int  _edgeY: _barInset + ShellSettings.barHeight + 8
    readonly property real _minX: radius + 4
    readonly property real _maxX: Math.max(_minX, win.width - width - _minX)

    property real scaleAmt: Motion.popScaleFrom
    property real edgeOffset: _closedOffset
    readonly property real _closedOffset: barBottom ? 8 : -8

    function _clampedX(px: real): real {
        return Math.max(_minX, Math.min(px, _maxX))
    }
    function _targetX(): real {
        const t = Math.max(0, Math.min(win.width, anchorX))
        return Math.round(_clampedX(t - width * t / Math.max(1, win.width)))
    }
    function place(): void {
        x = _targetX()
    }
    function reclamp(): void {
        const nx = Math.round(_clampedX(x))
        if (Math.abs(nx - x) > 0.5) x = nx
    }

    on_MinXChanged: reclamp()
    on_MaxXChanged: reclamp()
    onAnchorXChanged: place()
    onOpenChanged: {
        if (open) {
            _placementSettled = false
            place()
            _placementSettle.restart()
        } else {
            _placementSettle.stop()
            _placementSettled = false
        }
    }

    y: Math.round((barBottom ? (win.height - _edgeY - height) : _edgeY) + edgeOffset)
    radius: Theme.radiusPanel
    antialiasing: true
    color: Theme.popup
    border.width: 1
    border.color: Theme.outline

    transform: Scale { origin.x: root._originX; origin.y: root.barBottom ? root.height : 0; xScale: root.scaleAmt; yScale: root.scaleAmt }
    state: open ? "visible" : "hidden"
    layer.enabled: !ShellSettings.reduceMotion && opacity > 0.001 && scaleAmt < 0.999

    Behavior on x {
        enabled: root.state === "visible" && !ShellSettings.reduceMotion && root._placementSettled
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    Timer {
        id: _placementSettle
        interval: Motion.popSettle
        repeat: false
        onTriggered: root._placementSettled = true
    }

    Connections {
        target: root.win
        function onWidthChanged() {
            if (!root.open) return
            const nx = root._targetX()
            if (Math.abs(nx - root.x) > 0.5) root.place()
        }
    }

    Component.onCompleted: place()

    states: [
        State { name: "hidden";  PropertyChanges { root.scaleAmt: Motion.popScaleFrom; root.edgeOffset: root._closedOffset; root.opacity: 0 } },
        State { name: "visible"; PropertyChanges { root.scaleAmt: 1.0; root.edgeOffset: 0; root.opacity: 1 } }
    ]
    transitions: [
        Transition {
            from: "*"; to: "visible"
            ParallelAnimation {
                NumberAnimation { target: root; property: "scaleAmt";   to: 1.0; duration: Motion.popIn; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "edgeOffset"; to: 0;   duration: Motion.popIn; easing.type: Easing.OutQuart }
                NumberAnimation { target: root; property: "opacity";    to: 1.0; duration: Motion.popInFade; easing.type: Easing.OutCubic }
            }
        },
        Transition {
            from: "visible"; to: "hidden"
            ParallelAnimation {
                NumberAnimation { target: root; property: "scaleAmt";   to: Motion.popScaleFrom; duration: Motion.popOut; easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "edgeOffset"; to: root._closedOffset;  duration: Motion.popOut; easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "opacity";    to: 0.0; duration: Motion.popOutFade; easing.type: Easing.InCubic }
            }
        }
    ]
}
