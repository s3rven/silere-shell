pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

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

    activeFocusOnTab: shown
    Accessible.role: Accessible.Button
    Accessible.name: "Urgent workspace " + targetWs
    Accessible.description: "Activate to jump to it."
    Accessible.onPressAction: root._jump()

    function _jump(): void { if (shown) root.jumpRequested(targetWs) }
    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._jump(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._jump(); event.accepted = true }
    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._jump(); event.accepted = true }

    HoverHandler { id: _tickHover; enabled: root.shown; cursorShape: Qt.PointingHandCursor }
    TapHandler   { enabled: root.shown; onTapped: root._jump() }

    Rectangle {
        id: _tickFocusRing
        anchors.centerIn: parent
        width: parent.width
        height: root.rowHeight
        radius: Metrics.hoverRadiusFor(height)
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, 0.14)
        opacity: root.activeFocus ? 1.0 : 0.0
        visible: opacity > 0.001
        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        OutlineBorder {
            radius: _tickFocusRing.radius
            outlineColor: Theme.withAlpha(Theme.accent, Theme.focusRingAlpha)
        }
    }

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
        opacity: root._pulse * ((_tickHover.hovered || root.activeFocus) ? 1.0 : 0.9)
        scale: (_tickHover.hovered && ShellSettings.barHoverHighlight) || root.activeFocus ? 1.25 : 1.0
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
