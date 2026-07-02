import QtQuick
import "../../config"
import "../../services"

// Shared page chrome for the menu tabs: fade+scale enter/exit driven by
// `active`, GPU layer held only while entering. Pages become this, tune the
// timings, and hook pageShown()/pageHidden() for their own resets.
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
    layer.enabled: _entering && !ShellSettings.reduceMotion

    Component.onCompleted: opacity = root.active ? 1.0 : 0.0

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (root.opacity < 0.001) root.scale = root.scaleFrom
            _enter.restart()
            root.pageShown()
        } else {
            _enter.stop()
            _exit.restart()
            root.pageHidden()
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
