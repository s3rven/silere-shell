import QtQuick
import "../../config"
import "../../services"

// base for menu tab pages; override pageShown()/pageHidden() for per-page resets
Item {
    id: root

    required property bool active
    required property bool powerOpen

    property real slideFrom:  7
    property real slideOut:  -3
    property int  enterFade: 140
    property int  enterMove: 180
    property int  exitFade:  100
    property int  moveEasing: Easing.OutCubic

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001

    property bool _announcedActive: false
    property real _slide: 0
    // whole-pixel translate, not scale: scaling re-textures native text and wobbles glyphs
    transform: Translate { y: Math.round(root._slide) }

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

    function _settleVisuals(): void {
        _enter.stop()
        _exit.stop()
        root.opacity = root.active ? 1.0 : 0.0
        root._slide = 0
    }

    Component.onCompleted: {
        root.opacity = root.active ? 1.0 : 0.0
        root._slide = root.active ? 0 : root.slideFrom
        Qt.callLater(root._announceShown)
    }

    // false while the menu is closed and for the first cycle after it opens, so the
    // landing page rides the panel's scale-in instead of stacking a second enter on
    // top of it. only a tab switch (menu already settled open) plays the page enter.
    property bool _menuSettled: false
    Connections {
        target: MenuState
        function onOpenChanged() {
            root._menuSettled = false
            if (MenuState.open) Qt.callLater(() => root._menuSettled = true)
        }
    }

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (!root._menuSettled) { _settleVisuals(); root._announceShown(); return }
            if (root.opacity < 0.001) root._slide = root.slideFrom
            _enter.restart()
            root._announceShown()
        } else {
            _enter.stop()
            // menu closing: snap and let the panel carry it, don't double the motion
            if (!MenuState.open) { _settleVisuals(); root._announceHidden(); return }
            _exit.restart()
            root._announceHidden()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settleVisuals()
        }
    }

    ParallelAnimation {
        id: _enter
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(root.enterFade);  easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "_slide";  to: 0.0; duration: Motion.ms(root.enterMove); easing.type: root.moveEasing }
    }

    ParallelAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(root.exitFade); easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "_slide"; to: root.slideOut; duration: Motion.ms(root.exitFade); easing.type: Easing.InCubic }
    }
}
