import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    property int  enterFade: 140
    property int  exitFade:  100

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001

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

    // Opening appears with the popup's fade; tab switches only crossfade.
    property bool _menuOpenSettled: false
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (!MenuState.open) root._menuOpenSettled = false
            else Qt.callLater(() => root._menuOpenSettled = true)
        }
    }

    Component.onCompleted: {
        root.opacity = root.active ? 1.0 : 0.0
        if (MenuState.open) Qt.callLater(() => root._menuOpenSettled = true)
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (!root._menuOpenSettled) { root.opacity = 1.0; root._announceShown(); return }
            _enter.restart()
            root._announceShown()
        } else {
            _enter.stop()
            if (!MenuState.open) { root.opacity = 0.0; root._announceHidden(); return }
            _exit.restart()
            root._announceHidden()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (!ShellSettings.reduceMotion) return
            _enter.stop(); _exit.stop()
            root.opacity = root.active ? 1.0 : 0.0
        }
    }

    NumberAnimation { id: _enter; target: root; property: "opacity"; to: 1.0; duration: Motion.ms(root.enterFade); easing.type: Easing.OutCubic }
    NumberAnimation { id: _exit;  target: root; property: "opacity"; to: 0.0; duration: Motion.ms(root.exitFade); easing.type: Easing.InCubic }
}
