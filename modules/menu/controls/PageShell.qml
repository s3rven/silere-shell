import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    property bool animateOnCreate: false

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    property real _pageShift: 0
    property real _transitionDirection: 1
    transform: Translate { x: root._pageShift }

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
        root.opacity = shown ? 1.0 : 0.0
        root._pageShift = 0
        if (!MenuState.open) root._announceHidden()
    }

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
        if (MenuState.open) Qt.callLater(() => root._menuOpenSettled = MenuState.open)
        if (enterNow) Qt.callLater(function() {
            if (root.active && MenuState.open && root._motionAllowed) _enter.restart()
            else root.settleVisual(root.active)
        })
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        if (root.active) {
            _exit.stop()
            if (!root._menuOpenSettled || !root._motionAllowed) {
                root.settleVisual(true)
                root._announceShown()
                return
            }
            if (root.opacity < 0.01)
                root._pageShift = Motion.pageOffset * root._transitionDirection
            _enter.restart()
            root._announceShown()
        } else {
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
        else root._pageShift = 0
    }

    ParallelAnimation {
        id: _enter
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "_pageShift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }
    ParallelAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        NumberAnimation { target: root; property: "_pageShift"; to: -Motion.pageOffset * root._transitionDirection; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
    }
}
