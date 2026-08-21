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
            else Qt.callLater(() => root._menuOpenSettled = true)
        }
    }

    Component.onCompleted: {
        const enterNow = root.active && root.animateOnCreate
            && MenuState.open && !ShellSettings.reduceMotion
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        root.opacity = root.active && !enterNow ? 1.0 : 0.0
        root._pageShift = enterNow
            ? Motion.pageOffset * root._transitionDirection : 0
        if (MenuState.open) Qt.callLater(() => root._menuOpenSettled = true)
        if (enterNow) Qt.callLater(function() {
            if (root.active) _enter.restart()
        })
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        if (root.active) {
            _exit.stop()
            if (!root._menuOpenSettled) { root.opacity = 1.0; root._announceShown(); return }
            if (root.opacity < 0.01)
                root._pageShift = Motion.pageOffset * root._transitionDirection
            _enter.restart()
            root._announceShown()
        } else {
            _enter.stop()
            if (!MenuState.open) {
                return
            }
            _exit.restart()
            root._announceHidden()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (!ShellSettings.reduceMotion) return
            _enter.stop(); _exit.stop()
            if (!MenuState.open) {
                root._pageShift = 0
                return
            }
            root.opacity = root.active ? 1.0 : 0.0
            root._pageShift = 0
        }
    }

    ParallelAnimation {
        id: _enter
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel }
        NumberAnimation { target: root; property: "_pageShift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }
    ParallelAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        NumberAnimation { target: root; property: "_pageShift"; to: -Motion.pageOffset * root._transitionDirection; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
    }
}
