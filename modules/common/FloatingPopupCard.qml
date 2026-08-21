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
    property bool _hardClamping: false
    property bool _closing: false
    readonly property bool fullyShown: root.open && root._transitionReady
        && !_enterAnimation.running && root.opacity >= 0.999
    readonly property real _originX: Math.max(0, Math.min(targetWidth, anchorX - x))
    readonly property real motionOriginX: _originX

    property real _barInset: Metrics.barEdgeInset
    MotionBehavior on _barInset {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    readonly property real _edgeY: _barInset + ShellSettings.barHeight + 8
    readonly property real _minX: Metrics.snap4Up(radius + 4)
    readonly property real _maxX: Math.max(_minX,
        Metrics.snap4Down(win.width - targetWidth - _minX))

    property real scaleAmt: 1
    property real edgeOffset: 0
    opacity: 0

    function _hiddenScale(): real {
        return root.animateScale ? Motion.popScaleFrom : 1.0
    }

    function _hiddenEdge(): real {
        return root.barBottom ? Motion.popEdgeOffset : -Motion.popEdgeOffset
    }

    function _snapOpen(): void {
        _enterAnimation.stop()
        _exitAnimation.stop()
        root._closing = false
        root.scaleAmt = 1.0
        root.edgeOffset = 0.0
        root.opacity = 1.0
    }

    function _snapClosed(notify: bool): void {
        const shouldNotify = notify && (root._closing || root.opacity > 0.001)
        _enterAnimation.stop()
        _exitAnimation.stop()
        root.scaleAmt = root._hiddenScale()
        root.edgeOffset = root._hiddenEdge()
        root.opacity = 0.0
        root._closing = false
        if (shouldNotify) root.closeFinished()
    }

    function _startOpen(): void {
        _exitAnimation.stop()
        root._closing = false
        if (ShellSettings.reduceMotion) root._snapOpen()
        else _enterAnimation.restart()
    }

    function _startClose(): void {
        _enterAnimation.stop()
        if (root.opacity <= 0.001 && !_exitAnimation.running) {
            root._snapClosed(false)
            return
        }
        root._closing = true
        if (ShellSettings.reduceMotion) root._snapClosed(true)
        else _exitAnimation.restart()
    }

    function _clampedX(px: real): real {
        return Math.max(_minX, Math.min(px, _maxX))
    }
    function _targetX(): real {
        const t = Math.max(0, Math.min(win.width, anchorX))
        return Metrics.snap4(_clampedX(t - targetWidth * t / Math.max(1, win.width)))
    }
    function place(): void {
        x = _targetX()
    }
    function reclamp(): void {
        const nx = Metrics.snap4(_clampedX(x))
        if (Math.abs(nx - x) <= 0.5) return
        // Clamp corrections are geometry invariants, not placement motion.
        // Snapping also avoids retargeting x on every radius-animation frame.
        _hardClamping = true
        x = nx
        _hardClamping = false
    }

    onRadiusChanged: {
        if (ShellSettings.reduceMotion) root.reclamp()
        else _radiusReclamp.restart()
    }
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
        if (!_transitionReady) {
            if (!open) {
                _startupFrame.stop()
            } else if (ShellSettings.reduceMotion) {
                _transitionReady = true
                root._snapOpen()
            } else {
                _startupFrame.start()
            }
            return
        }
        if (open) root._startOpen()
        else root._startClose()
    }

    onBarBottomChanged: if (!root.open && !_exitAnimation.running)
        root.edgeOffset = root._hiddenEdge()

    y: Metrics.popupY(win.height, height, barBottom, _edgeY)
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
    layer.enabled: root.animateScale && !ShellSettings.reduceMotion
        && opacity > 0.001 && (scaleAmt < 0.999 || !root.open)

    MotionBehavior on x {
        gate: root.animatePlacement && root.open && root._transitionReady
            && root._placementSettled && !root._hardClamping
        NumberAnimation {
            duration: Motion.medium
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
    }

    Timer {
        id: _placementSettle
        interval: Motion.popSettle
        repeat: false
        onTriggered: root._placementSettled = true
    }

    Timer {
        id: _radiusReclamp
        interval: 40
        onTriggered: root.reclamp()
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (!ShellSettings.reduceMotion) return
            if (!root._transitionReady) {
                _startupFrame.stop()
                root._transitionReady = true
            }
            if (root.open) root._snapOpen()
            else root._snapClosed(true)
            _radiusReclamp.stop()
            root.reclamp()
        }
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
        root._snapClosed(false)
        if (ShellSettings.reduceMotion) {
            root._transitionReady = true
            if (root.open) root._startOpen()
        } else if (root.open) {
            _startupFrame.start()
        }
    }

    // Let the new scene graph synchronize once before revealing the card. A
    // popup is a lazily-created window; starting its entrance in Component.onCompleted
    // makes construction and the first visible animation frame compete on the GUI thread.
    FrameAnimation {
        id: _startupFrame
        running: false
        onTriggered: {
            stop()
            root._transitionReady = true
            if (root.open) root._startOpen()
        }
    }

    ParallelAnimation {
        id: _enterAnimation
        NumberAnimation { target: root; property: "scaleAmt";  to: 1.0; duration: root.animateScale ? Motion.popIn : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        NumberAnimation { target: root; property: "edgeOffset"; to: 0.0; duration: Motion.popIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        NumberAnimation { target: root; property: "opacity";   to: 1.0; duration: Motion.popInFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel }
    }

    ParallelAnimation {
        id: _exitAnimation
        NumberAnimation { target: root; property: "scaleAmt"; to: root._hiddenScale(); duration: root.animateScale ? Motion.popOut : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        NumberAnimation { target: root; property: "edgeOffset"; to: root._hiddenEdge(); duration: Motion.popOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.popOutFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        onFinished: {
            if (root.open || !root._closing) return
            // Target inputs (notably bar edge) can change mid-exit. Normalize
            // to today's hidden state before the next open reverses from it.
            root.scaleAmt = root._hiddenScale()
            root.edgeOffset = root._hiddenEdge()
            root.opacity = 0.0
            root._closing = false
            root.closeFinished()
        }
    }
}
