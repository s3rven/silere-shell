import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string text: ""
    property color  color: Theme.text

    clip: _roll.running
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    // whole px so neighbours in a Row don't land on fractional pixels
    implicitWidth:  Math.ceil(_main.implicitWidth)
    implicitHeight: _main.implicitHeight
    width:  implicitWidth
    height: implicitHeight
    MotionBehavior on width {
        gate: root._ready
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    readonly property real _dist: Math.max(6, implicitHeight * 0.6)

    property string _shown: ""
    property bool   _ready: false
    Component.onCompleted: {
        _shown = text
        Qt.callLater(function() { if (root) root._ready = true })
    }

    function _settle(): void {
        _roll.stop()
        _shown = text
        _main.rise = 0
        _main.opacity = 1
        _ghost.rise = 0
        _ghost.opacity = 0
    }

    onTextChanged: {
        if (_shown === text) return
        if (!_ready || !visible || ShellSettings.reduceMotion) {
            _settle()
            return
        }
        _ghost.text = _shown
        _shown = text
        _roll.restart()
    }
    onVisibleChanged: if (!visible && _ready) _settle()

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion && root._ready) root._settle()
        }
    }

    ShellText {
        id: _main
        anchors.verticalCenter: parent.verticalCenter
        text:           root._shown
        color:          root.color
        font.pixelSize: Settings.fontSize
        property real rise: 0
        transform: Translate { y: _main.rise }
        ColorFade on color {}
    }

    ShellText {
        id: _ghost
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0
        visible: opacity > 0.001
        color:          root.color
        font.pixelSize: Settings.fontSize
        property real rise: 0
        transform: Translate { y: _ghost.rise }
        ColorFade on color {}
    }

    ParallelAnimation {
        id: _roll
        NumberAnimation { target: _ghost; property: "rise";    from: 0;          to: -root._dist; duration: Motion.ms(170); easing.type: Easing.InCubic  }
        NumberAnimation { target: _ghost; property: "opacity"; from: 1;          to: 0;           duration: Motion.ms(130); easing.type: Easing.InCubic  }
        NumberAnimation { target: _main;  property: "rise";    from: root._dist; to: 0;           duration: Motion.ms(220); easing.type: Easing.OutQuart }
        NumberAnimation { target: _main;  property: "opacity"; from: 0;          to: 1;           duration: Motion.ms(170); easing.type: Easing.OutCubic }
    }
}
