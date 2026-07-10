import QtQuick
import "../../config"
import "../../services"

// base for menu tab pages; override pageShown()/pageHidden() for per-page resets
Item {
    id: root

    required property bool active
    required property bool powerOpen

    property real scaleFrom:   0.97
    property int  enterFade:   140
    property int  enterScale:  180
    property int  exitFade:    100
    property int  scaleEasing: Easing.OutCubic

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    transformOrigin: Item.Center

    property bool _entering: false
    property bool _announcedActive: false
    layer.enabled: _entering && !ShellSettings.reduceMotion

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
        root._entering = false
        root.opacity = root.active ? 1.0 : 0.0
        root.scale = 1.0
    }

    Component.onCompleted: {
        root.opacity = root.active ? 1.0 : 0.0
        root.scale = root.active ? 1.0 : root.scaleFrom
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (root.opacity < 0.001) root.scale = root.scaleFrom
            _enter.restart()
            root._announceShown()
        } else {
            _enter.stop()
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
        onStarted: root._entering = true
        onStopped: root._entering = false
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(root.enterFade);  easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale";   to: 1.0; duration: Motion.ms(root.enterScale); easing.type: root.scaleEasing }
    }

    SequentialAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(root.exitFade); easing.type: Easing.InCubic }
        ScriptAction { script: root.scale = 1.0 }
    }
}
