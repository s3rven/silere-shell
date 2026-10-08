import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    property bool animateOnCreate: false
    // A page with an asynchronous body begins its reveal when that body is
    // ready, so the fade does not finish over an empty header.
    property bool revealReady: true
    // A widening panel can have its body ready before there is room to paint it.
    property bool viewportReady: true
    property bool _awaitingEnter: false

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    property real _pageShift: 0
    property real _pageLift: 0
    property real _transitionDirection: 1
    transform: Translate { x: root._pageShift; y: root._pageLift }

    readonly property bool _motionAllowed: Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    property bool _announcedActive: false

    function _announceShown(): void {
        if (!root.active || root._announcedActive) return
        root._announcedActive = true
        root.pageShown()
    }

    function _announceHidden(): void {
        if (!root._announcedActive) return
        root._announcedActive = false
        root.pageHidden()
    }

    function settleVisual(shown: bool): void {
        _enter.stop()
        _exit.stop()
        root._awaitingEnter = false
        root.opacity = shown ? 1.0 : 0.0
        root._pageShift = 0
        root._pageLift = 0
        if (!MenuState.open) root._announceHidden()
    }

    function _startEnter(): void {
        if (!root._awaitingEnter || !root.revealReady || !root.viewportReady || !root.active) return
        root._awaitingEnter = false
        if (!MenuState.open || !root._motionAllowed) root.settleVisual(root.active)
        else _enter.restart()
    }

    function _prepareEnter(): void {
        if (root.opacity < 0.01) {
            root._pageShift = Motion.pageOffset * root._transitionDirection
            root._pageLift = Motion.pageLift
        }
        root._awaitingEnter = true
        root._startEnter()
    }

    onRevealReadyChanged: if (root.revealReady) root._startEnter()
    onViewportReadyChanged: if (root.viewportReady) root._startEnter()

    property bool _menuOpenSettled: false
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (!MenuState.open) root._menuOpenSettled = false
            else Qt.callLater(() => root._menuOpenSettled = MenuState.open)
        }
    }

    Component.onCompleted: {
        const enterNow = root.active && root.animateOnCreate
            && MenuState.open && root._motionAllowed
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        root.opacity = root.active && !enterNow ? 1.0 : 0.0
        root._pageShift = enterNow
            ? Motion.pageOffset * root._transitionDirection : 0
        root._pageLift = enterNow ? Motion.pageLift : 0
        if (MenuState.open) Qt.callLater(() => root._menuOpenSettled = MenuState.open)
        if (enterNow) Qt.callLater(function() {
            if (root.active && MenuState.open && root._motionAllowed) root._prepareEnter()
            else root.settleVisual(root.active)
        })
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        if (root.active) {
            _exit.stop()
            // PageShown can select another body on a retained settings page.
            // Announce first, then test whether that body is ready to reveal.
            root._announceShown()
            if (!root._menuOpenSettled || !root._motionAllowed) {
                root.settleVisual(true)
                return
            }
            root._prepareEnter()
        } else {
            root._awaitingEnter = false
            _enter.stop()
            if (!MenuState.open) {
                return
            }
            if (root._motionAllowed) _exit.restart()
            else root.settleVisual(false)
            root._announceHidden()
        }
    }

    on_MotionAllowedChanged: {
        if (root._motionAllowed) return
        _enter.stop()
        _exit.stop()
        if (MenuState.open) root.settleVisual(root.active)
        else {
            root._pageShift = 0
            root._pageLift = 0
        }
    }

    ParallelAnimation {
        id: _enter
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "_pageShift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        NumberAnimation { target: root; property: "_pageLift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }
    ParallelAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        NumberAnimation { target: root; property: "_pageShift"; to: -Motion.pageOffset * root._transitionDirection; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        NumberAnimation { target: root; property: "_pageLift"; to: -Motion.pageLift; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
    }
}
