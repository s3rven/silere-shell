import QtQuick
import "../../config"
import "../../services"

// Value change rolls vertically (old drifts up/fades, new rises). For slow tickers (clock minute, date), not per-second.
Item {
    id: root

    property string text: ""
    property color  color: Theme.text

    // clip only mid-roll — at rest text fits its box, so no permanent clip pass on the bar
    clip: _roll.running
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    // Whole px so neighbours in a Row don't land on fractional pixels.
    implicitWidth:  Math.ceil(_main.implicitWidth)
    implicitHeight: _main.implicitHeight
    width:  implicitWidth
    height: implicitHeight
    // Smooth the rare width change (9:59 → 10:00) so the row glides, not jumps.
    Behavior on width { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    // travel scales with the line so it reads the same at any font size
    readonly property real _dist: Math.max(6, implicitHeight * 0.6)

    property string _shown: ""
    property bool   _ready: false
    Component.onCompleted: { _shown = text; _ready = true }

    onTextChanged: {
        if (_shown === text) return
        if (!_ready || ShellSettings.reduceMotion) { _shown = text; return }
        _ghost.text = _shown   // snapshot the outgoing string
        _shown = text
        _roll.restart()
    }

    Text {
        id: _main
        anchors.verticalCenter: parent.verticalCenter
        text:           root._shown
        color:          root.color
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        renderType:     Text.NativeRendering
        property real rise: 0
        transform: Translate { y: _main.rise }
        Behavior on color { ColorAnimation { duration: Motion.color } }
    }

    Text {
        id: _ghost
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0
        visible: opacity > 0.001
        color:          root.color
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        renderType:     Text.NativeRendering
        property real rise: 0
        transform: Translate { y: _ghost.rise }
        Behavior on color { ColorAnimation { duration: Motion.color } }
    }

    ParallelAnimation {
        id: _roll
        NumberAnimation { target: _ghost; property: "rise";    from: 0;          to: -root._dist; duration: Motion.ms(170); easing.type: Easing.InCubic  }
        NumberAnimation { target: _ghost; property: "opacity"; from: 1;          to: 0;           duration: Motion.ms(130); easing.type: Easing.InCubic  }
        NumberAnimation { target: _main;  property: "rise";    from: root._dist; to: 0;           duration: Motion.ms(220); easing.type: Easing.OutQuart }
        NumberAnimation { target: _main;  property: "opacity"; from: 0;          to: 1;           duration: Motion.ms(170); easing.type: Easing.OutCubic }
    }
}
