pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Rectangle {
    id: root

    required property var win
    required property bool open
    required property real anchorX
    required property bool barBottom
    // clamp against the width the card is headed for, not the live one, or an animating width fights the x Behavior every frame
    property real targetWidth: width
    property bool animateScale: true
    property bool animatePlacement: true

    signal closeFinished()

    property bool _transitionReady: false
    property bool _placementSettled: false
    readonly property real _originX: Math.max(0, Math.min(targetWidth, anchorX - x))

    property real _barInset: ShellSettings.barFloating ? 4 : 0
    MotionBehavior on _barInset {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    readonly property int  _edgeY: _barInset + ShellSettings.barHeight + 8
    readonly property real _minX: radius + 4
    readonly property real _maxX: Math.max(_minX, win.width - targetWidth - _minX)

    property real scaleAmt: animateScale ? Motion.popScaleFrom : 1
    property real edgeOffset: barBottom ? Motion.popEdgeOffset : -Motion.popEdgeOffset
    opacity: 0

    function _clampedX(px: real): real {
        return Math.max(_minX, Math.min(px, _maxX))
    }
    function _targetX(): real {
        const t = Math.max(0, Math.min(win.width, anchorX))
        return Math.round(_clampedX(t - targetWidth * t / Math.max(1, win.width)))
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
    // place() not reclamp(): clamping the old x makes a widening card grow from its left edge
    onTargetWidthChanged: if (open) place()
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

    y: Math.round(barBottom ? (win.height - _edgeY - height) : _edgeY)
    radius: Theme.surfaceRadius
    antialiasing: true
    color: Theme.popup

    OutlineBorder {
        radius: root.radius
        outlineColor: Theme.outline
    }

    transform: [
        Translate { y: root.edgeOffset },
        Scale {
            origin.x: root._originX
            origin.y: root.barBottom ? root.height : 0
            xScale: root.scaleAmt
            yScale: root.scaleAmt
        }
    ]
    state: open && _transitionReady ? "visible" : "hidden"
    layer.enabled: root.animateScale && !ShellSettings.reduceMotion
        && opacity > 0.001 && (scaleAmt < 0.999 || !root.open)

    MotionBehavior on x {
        gate: root.animatePlacement && root.state === "visible" && root._placementSettled
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

    Component.onCompleted: {
        place()
        if (root.open) _placementSettle.restart()
        Qt.callLater(function() { root._transitionReady = true })
    }

    states: [
        State {
            name: "hidden"
            PropertyChanges {
                root.scaleAmt: root.animateScale ? Motion.popScaleFrom : 1.0
                root.edgeOffset: root.barBottom ? Motion.popEdgeOffset : -Motion.popEdgeOffset
                root.opacity: 0
            }
        },
        State {
            name: "visible"
            PropertyChanges {
                root.scaleAmt: 1.0
                root.edgeOffset: 0
                root.opacity: 1
            }
        }
    ]
    transitions: [
        Transition {
            from: "*"; to: "visible"
            ParallelAnimation {
                NumberAnimation { target: root; property: "scaleAmt";  to: 1.0; duration: root.animateScale ? Motion.popIn : 0; easing.type: Easing.OutQuart }
                NumberAnimation { target: root; property: "edgeOffset"; to: 0.0; duration: Motion.popIn; easing.type: Easing.OutQuart }
                NumberAnimation { target: root; property: "opacity";   to: 1.0; duration: Motion.popInFade; easing.type: Easing.OutCubic }
            }
        },
        Transition {
            from: "visible"; to: "hidden"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: root; property: "scaleAmt"; to: root.animateScale ? Motion.popScaleFrom : 1.0; duration: root.animateScale ? Motion.popOut : 0; easing.type: Easing.InCubic }
                    NumberAnimation { target: root; property: "edgeOffset"; to: root.barBottom ? Motion.popEdgeOffset : -Motion.popEdgeOffset; duration: Motion.popOut; easing.type: Easing.InCubic }
                    NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.popOutFade; easing.type: Easing.InCubic }
                }
                ScriptAction { script: root.closeFinished() }
            }
        }
    ]
}
