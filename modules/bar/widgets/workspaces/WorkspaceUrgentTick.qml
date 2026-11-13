pragma ComponentBehavior: Bound

import QtQuick
import "../../../common"
import "../../../../config"
import "../../../../services"

Item {
    id: root

    required property int liveId
    required property real rowHeight
    required property bool barActive
    property bool before: false
    property real hitTop: 0
    property real hitBottom: 0

    signal jumpRequested(int wsId)

    readonly property bool shown: liveId > 0
    property int targetWs: 0
    // the strip's side flips to before once nothing is urgent, possibly ahead of liveId: a fading arrow keeps its own
    property bool _shownBefore: false
    function _latchSide(): void { if (root.shown) root._shownBefore = root.before }
    onBeforeChanged: Qt.callLater(root._latchSide)

    onLiveIdChanged: if (liveId > 0) {
        if (targetWs !== liveId) _pulseSettled = false
        targetWs = liveId
        Qt.callLater(root._latchSide)
    }
    Component.onCompleted: if (liveId > 0) {
        targetWs = liveId
        _shownBefore = before
    }

    implicitWidth: Math.max(rowHeight, Math.ceil(_label.implicitWidth) + 12)
    width: implicitWidth
    height: rowHeight
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    MotionBehavior on opacity {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    readonly property bool canActivate: root.enabled && root.visible && root.shown
        && root.barActive && !Idle.isIdle
    function _jump(): void { if (root.canActivate) root.jumpRequested(targetWs) }

    Accessible.role: Accessible.Button
    Accessible.name: "Go to workspace " + root.targetWs
    Accessible.description: "Needs attention. " + (root.before ? "Before" : "After") + " the current page"
    Accessible.focusable: root.canActivate
    Accessible.onPressAction: root._jump()
    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

    Item {
        objectName: "workspace-tick-hit"
        y: -root.hitTop
        width: root.width
        height: root.height + root.hitTop + root.hitBottom
        HoverHandler { id: _tickHover; enabled: root.canActivate; cursorShape: Qt.PointingHandCursor }
        TapHandler   { enabled: root.canActivate; onTapped: root._jump() }
    }

    property real _pulse: 1.0
    property bool _pulseSettled: false
    readonly property bool _motionActive: root.visible && root.shown && !root._pulseSettled
        && ShellSettings.wsUrgentPulse && root.barActive
        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    onShownChanged: if (shown) _pulseSettled = false
    SequentialAnimation {
        running: root._motionActive
        loops:   Animation.Infinite
        onRunningChanged: if (!running) root._pulse = 1.0
        NumberAnimation { target: root; property: "_pulse"; to: 0.35; duration: Motion.ms(550); easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_pulse"; to: 1.0;  duration: Motion.ms(550); easing.type: Easing.InOutSine }
    }
    Timer {
        interval: 15000
        running: root._motionActive
        onTriggered: root._pulseSettled = true
    }

    ShellText {
        id: _label
        anchors.centerIn: parent
        text: (root._shownBefore ? "‹ " : "› ") + root.targetWs
        font.pixelSize: Settings.fontLabel
        color: Theme.warning
        opacity: root._pulse * ((_tickHover.hovered) ? 1.0 : 0.9)
        scale: (_tickHover.hovered && ShellSettings.barHoverHighlight) ? 1.08 : 1.0
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
