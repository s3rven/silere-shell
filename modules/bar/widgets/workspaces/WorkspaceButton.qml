pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"
import "../../../common"

Item {
    id: root

    required property int wsId
    required property bool monitorReady
    required property bool active
    required property bool occupied
    required property bool urgent
    required property var apps
    required property bool compact
    required property int iconSize
    required property real cellWidth
    required property real rowHeight
    required property bool barActive
    required property bool initialized
    required property bool paging
    required property bool markerCovers

    signal activateRequested()
    signal anchorMenuRequested()
    signal quickActionsRequested()
    signal markerPulseRequested()
    signal hoverReported(int wsId, bool on)

    readonly property bool hovered: _hover.hovered
    readonly property bool _hoverFx: hovered && ShellSettings.barHoverHighlight
    // an underline marker leaves the cell centre free, so the active workspace keeps its own content
    readonly property bool _blanked: active && markerCovers
    readonly property bool _showIcons: ShellSettings.wsShowAppIcons && !_blanked && apps.length > 0

    width:  cellWidth
    height: rowHeight

    MotionBehavior on width {
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: {
        _dotFade = _blanked ? 0 : 1
        if (!initialized || ShellSettings.reduceMotion || paging) return
        scale = 0
        _enterAnim.start()
    }
    Component.onDestruction: if (root.hovered) root.hoverReported(root.wsId, false)

    SequentialAnimation {
        id: _enterAnim
        NumberAnimation { target: root; property: "scale"; to: 1.0; duration: Motion.ms(130); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _dropPulse
        NumberAnimation { target: root; property: "scale"; to: 1.12; duration: Motion.ms(70);  easing.type: Easing.OutQuad  }
        NumberAnimation { target: root; property: "scale"; to: 1.0;  duration: Motion.ms(145); easing.type: Easing.OutCubic }
    }

    function _activate(): void {
        if (!root.monitorReady) return
        if (root.active) {
            root.markerPulseRequested()
            root.anchorMenuRequested()
        } else {
            root.activateRequested()
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: "Workspace " + root.wsId
    Accessible.selected: root.active
    Accessible.focusable: true
    Accessible.onPressAction: root._activate()

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }
    onHoveredChanged: root.hoverReported(root.wsId, root.hovered)

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.MiddleButton) {
                if (!Compositor.activeToplevel) return
                Compositor.moveActiveToWorkspace(root.wsId)
                if (!ShellSettings.reduceMotion) _dropPulse.restart()
                return
            }
            if (button === Qt.RightButton) {
                if (root.active) {
                    root.markerPulseRequested()
                    root.quickActionsRequested()
                }
                return
            }
            root._activate()
        }
    }

    on_BlankedChanged: {
        if (ShellSettings.reduceMotion) { _dotFade = _blanked ? 0 : 1; return }
        _dotFadeOut.stop(); _dotFadeIn.stop()
        if (_blanked) _dotFadeOut.restart()
        else          _dotFadeIn.restart()
    }
    onActiveChanged: if (root.active) root.clearMarkerPass()
    onPagingChanged: if (root.paging) root.clearMarkerPass()

    readonly property real _pulseOpacity: _urgentFx.item ? _urgentFx.item.pulseOpacity : 1.0
    readonly property real _shakeX: _urgentFx.item ? _urgentFx.item.shakeX : 0
    property real _dotFade: 1.0
    property real _markerPassCover: 0.0
    property int _markerPassDelayMs: 0
    readonly property bool markerPassActive: _markerPassAnim.running
    property bool _notifPulseLoaded: false
    property bool _notifPulseCritical: false

    function playMarkerPass(delayMs: int): void {
        if (!root.barActive || root.active || root.paging || !root.markerCovers
                || !ShellSettings.workspaceShift || ShellSettings.reduceMotion
                || Idle.isIdle) return
        // restart from full opacity; a second jump must not resume the first one's fade
        _markerPassAnim.stop()
        root._markerPassCover = 0
        root._markerPassDelayMs = Math.max(0, Math.min(144, delayMs))
        _markerPassAnim.start()
    }

    function clearMarkerPass(): void {
        if (!_markerPassAnim.running && root._markerPassCover === 0) return
        _markerPassAnim.stop()
        root._markerPassCover = 0
    }

    function playNotificationPulse(critical: bool): void {
        if (!root.barActive || !ShellSettings.wsNotifPulse
                || ShellSettings.reduceMotion || Idle.isIdle) return
        _pulseUnload.stop()
        root._notifPulseCritical = critical
        if (_notifPulse.item) _notifPulse.item.play(critical)
        else root._notifPulseLoaded = true
    }

    Timer {
        id: _pulseUnload
        interval: 0
        onTriggered: root._notifPulseLoaded = false
    }
    readonly property bool _hoverReveal: ShellSettings.valuesOnHover && hovered
        && !_blanked && (_showIcons || !ShellSettings.wsShowNumbers)
    property real _revealAmt: _hoverReveal ? 1 : 0
    MotionBehavior on _revealAmt {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    property real _dotAlpha: urgent ? 0.95 : active ? 1.0 : occupied ? 0.65 : 0.28
    MotionBehavior on _dotAlpha {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    Loader {
        id: _notifPulse
        anchors.fill: parent
        z: -1
        active: root._notifPulseLoaded
        onLoaded: if (item) item.play(root._notifPulseCritical)
        sourceComponent: Component {
            WorkspaceNotifPulse {
                barActive: root.barActive
                onFinished: _pulseUnload.restart()
            }
        }
    }

    NumberAnimation {
        id: _dotFadeOut
        target: root; property: "_dotFade"; to: 0
        duration: Motion.ms(120); easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: _dotFadeIn
        PauseAnimation  { duration: Motion.ms(150) }
        NumberAnimation { target: root; property: "_dotFade"; to: 1; duration: Motion.ms(220); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _markerPassAnim
        PauseAnimation { duration: root._markerPassDelayMs }
        NumberAnimation {
            target: root; property: "_markerPassCover"; to: 1
            duration: Motion.ms(72); easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: Motion.ms(16) }
        NumberAnimation {
            target: root; property: "_markerPassCover"; to: 0
            duration: Motion.ms(145); easing.type: Easing.OutCubic
        }
    }
    Loader {
        id: _urgentFx
        active: root.urgent && !root.active && ShellSettings.wsUrgentPulse
        sourceComponent: Component {
            WorkspaceUrgentFx { barActive: root.barActive }
        }
    }

    Item {
        anchors.fill: parent
        opacity: 1 - root._markerPassCover

        ShellText {
            anchors.centerIn: parent
            transform: Translate { x: root._shakeX }
            text:    root.wsId
            opacity: (root._showIcons
                    ? root._revealAmt
                    : Math.max(ShellSettings.wsShowNumbers ? 1 : 0, root._revealAmt))
                * (root._blanked ? 0 : 1) * root._pulseOpacity * ShellSettings.wsMarkerOpacity
            scale:   root._blanked ? 0.6 : (root._hoverFx ? 1.12 : 1)
            color:   root.urgent
                ? Theme.warning
                : root.active
                ? Theme.accent
                : (root.occupied
                    ? (root._hoverFx ? Theme.accent : Theme.withAlpha(Theme.text, 0.85))
                    : (root._hoverFx ? Theme.withAlpha(Theme.accent, 0.65) : Theme.withAlpha(Theme.subtext, 0.45)))
            font.pixelSize: Settings.fontLabel

            MotionBehavior on opacity {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
            ColorFade on color {}
        }

        Rectangle {
            anchors.centerIn: parent
            transform: Translate { x: root._shakeX }
            width:  root.urgent ? 6 : (root.active || root.occupied ? 5 : 4)
            height: width
            radius: width / 2
            antialiasing: true
            visible: !ShellSettings.wsShowNumbers && !root._showIcons
            opacity: (1 - root._revealAmt) * root._dotFade
                * (root._hoverFx && !root.urgent ? Math.min(1, root._dotAlpha + 0.18)
                    : root._dotAlpha)
                * root._pulseOpacity * ShellSettings.wsMarkerOpacity
            color: root.urgent ? Theme.warning
                 : root.active ? Theme.accent
                 : Theme.withAlpha(Theme.subtext, 0.85)
            scale: root._hoverFx ? 1.2 : 1.0

            ColorFade on color {}
            MotionBehavior on width {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
        }

        Loader {
            anchors.centerIn: parent
            transform: Translate { x: root._shakeX }
            opacity: 1 - root._revealAmt
            active: root._showIcons
            sourceComponent: Component {
                WorkspaceAppIcons {
                    apps: root.compact ? root.apps.slice(0, 1) : root.apps
                    iconSize: root.iconSize
                    hoverFx: root._hoverFx
                    pulseOpacity: root._pulseOpacity
                }
            }
        }
    }
}
