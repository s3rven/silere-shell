pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"

Item {
    id: root

    required property int liveId
    required property real rowHeight
    required property bool barActive

    signal jumpRequested(int wsId)

    readonly property bool shown: liveId > 0
    property int targetWs: 0

    onLiveIdChanged: if (liveId > 0) {
        if (targetWs !== liveId) _pulseSettled = false
        targetWs = liveId
    }
    Component.onCompleted: if (liveId > 0) targetWs = liveId

    width: 10
    height: rowHeight
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    MotionBehavior on opacity {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    function _jump(): void { if (shown) root.jumpRequested(targetWs) }

    HoverHandler { id: _tickHover; enabled: root.shown; cursorShape: Qt.PointingHandCursor }
    TapHandler   { enabled: root.shown; onTapped: root._jump() }

    property real _pulse: 1.0
    property bool _pulseSettled: false
    onShownChanged: if (shown) _pulseSettled = false
    SequentialAnimation {
        running: root.shown && !root._pulseSettled
            && root.barActive && !ShellSettings.reduceMotion && !Idle.isIdle
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root._pulse = 1.0
        NumberAnimation { target: root; property: "_pulse"; to: 0.35; duration: Motion.ms(550); easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_pulse"; to: 1.0;  duration: Motion.ms(550); easing.type: Easing.InOutSine }
    }
    Timer {
        interval: 15000
        running: root.shown && !root._pulseSettled && root.barActive && !Idle.isIdle
        onTriggered: root._pulseSettled = true
    }

    Rectangle {
        anchors.centerIn: parent
        width:  5
        height: 5
        radius: 2.5
        antialiasing: true
        color: Theme.warning
        opacity: root._pulse * ((_tickHover.hovered) ? 1.0 : 0.9)
        scale: (_tickHover.hovered && ShellSettings.barHoverHighlight) ? 1.25 : 1.0
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
