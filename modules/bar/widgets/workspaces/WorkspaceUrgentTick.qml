pragma ComponentBehavior: Bound

import QtQuick
import "../../../common"
import "../../../../config"
import "../../../../services"

Item {
    id: root

    required property int liveId
    // a target the strip cannot number: a scratchpad's name, or a workspace on a monitor without a bar
    property string liveLabel: ""
    required property real rowHeight
    required property bool barActive
    property bool before: false
    property real hitTop: 0
    property real hitBottom: 0

    signal jumpRequested(int wsId)

    readonly property bool shown: liveId > 0 || liveLabel.length > 0
    property int targetWs: 0
    property string targetLabel: ""
    // the strip's side flips to before once nothing is urgent, possibly ahead of liveId: a fading arrow keeps its own
    property bool _shownBefore: false
    function _latchSide(): void { if (root.shown) root._shownBefore = root.before }
    onBeforeChanged: Qt.callLater(root._latchSide)

    // the last target stays latched while the tick fades out. Read from the inputs: shown may not have caught up yet
    function _latchTarget(): void {
        if (root.liveId <= 0 && root.liveLabel.length === 0) return
        const label = root.liveId > 0 ? "" : root.liveLabel
        if (root.targetWs !== root.liveId || root.targetLabel !== label) root._pulseSettled = false
        root.targetWs = root.liveId
        root.targetLabel = label
        Qt.callLater(root._latchSide)
    }
    onLiveIdChanged: root._latchTarget()
    onLiveLabelChanged: root._latchTarget()
    Component.onCompleted: if (shown) {
        targetWs = liveId
        targetLabel = liveId > 0 ? "" : liveLabel
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
    Accessible.name: root.targetLabel.length > 0 ? "Go to the window that needs attention"
        : "Go to workspace " + root.targetWs
    Accessible.description: root.targetLabel.length > 0
        ? "Needs attention. On " + (/^[0-9]+$/.test(root.targetLabel) ? "workspace " : "") + root.targetLabel
        : "Needs attention. " + (root.before ? "Before" : "After") + " the current page"
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
        text: (root._shownBefore ? "‹ " : "› ") + (root.targetLabel.length > 0 ? root.targetLabel : root.targetWs)
        font.pixelSize: Settings.fontLabel
        color: Theme.barInk(Theme.barWarning, true)
        readonly property bool _hot: _tickHover.hovered && ShellSettings.barHoverHighlight
        opacity: root._pulse * (_label._hot ? 1.0 : 0.9)
        scale: _label._hot ? 1.08 : 1.0
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
}
