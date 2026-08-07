pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    required property int wsId
    required property int index
    required property int siblingCount
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
    signal focusSiblingRequested(int index)
    signal hoverReported(int wsId, bool on)

    readonly property bool hovered: _hover.hovered
    readonly property bool _hoverFx: hovered && ShellSettings.barHoverHighlight
    // an underline marker leaves the cell centre free, so the active workspace keeps its own content
    readonly property bool _blanked: active && markerCovers
    readonly property bool _showIcons: ShellSettings.wsShowAppIcons && !_blanked && apps.length > 0

    width:  cellWidth
    height: rowHeight
    scale:  1.0

    MotionBehavior on width {
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    activeFocusOnTab: monitorReady

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

    function _appSummary(): string {
        const names = []
        for (let i = 0; i < root.apps.length; i++)
            names.push(root.apps[i].count > 1 ? root.apps[i].name + " ×" + root.apps[i].count : root.apps[i].name)
        return names.join(", ")
    }

    Accessible.role: Accessible.Button
    Accessible.name: "Workspace " + wsId
    Accessible.description: active ? "Current workspace"
        : urgent ? "Urgent workspace"
        : occupied ? (apps.length > 0
            ? "Occupied workspace: " + root._appSummary()
            : "Occupied workspace")
        : "Empty workspace"
    Accessible.focusable: monitorReady
    Accessible.onPressAction: root._activate()

    function _activate(): void {
        if (!root.monitorReady) return
        if (root.active) {
            root.markerPulseRequested()
            root.anchorMenuRequested()
        } else {
            root.activateRequested()
        }
    }

    Keys.onSpacePressed: event => {
        if (!event.isAutoRepeat) root._activate()
        event.accepted = true
    }
    Keys.onReturnPressed: event => {
        if (!event.isAutoRepeat) root._activate()
        event.accepted = true
    }
    Keys.onEnterPressed: event => {
        if (!event.isAutoRepeat) root._activate()
        event.accepted = true
    }
    Keys.onLeftPressed:  event => { root.focusSiblingRequested(root.index - 1); event.accepted = true }
    Keys.onRightPressed: event => { root.focusSiblingRequested(root.index + 1); event.accepted = true }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            root.focusSiblingRequested(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            root.focusSiblingRequested(root.siblingCount - 1)
            event.accepted = true
        }
    }

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }
    onHoveredChanged: root.hoverReported(root.wsId, root.hovered)

    WorkspaceFocusRing {
        rowHeight: root.rowHeight
        shown: root.activeFocus
    }

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

    readonly property real _pulseOpacity: _urgentFx.item ? _urgentFx.item.pulseOpacity : 1.0
    readonly property real _shakeX: _urgentFx.item ? _urgentFx.item.shakeX : 0
    property real _dotFade: 1.0
    readonly property bool _hoverReveal: ShellSettings.valuesOnHover && hovered
        && !_blanked && (_showIcons || !ShellSettings.wsShowNumbers)
    property real _revealAmt: _hoverReveal ? 1 : 0
    MotionBehavior on _revealAmt {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    property real _dotAlpha: urgent ? 0.95 : active ? 1.0 : occupied ? 0.65 : 0.28
    MotionBehavior on _dotAlpha {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    Loader {
        anchors.fill: parent
        z: -1
        active: ShellSettings.wsNotifPulse
        sourceComponent: Component {
            WorkspaceNotifPulse {
                workspaceId: root.wsId
                barActive: root.barActive
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

    Loader {
        id: _urgentFx
        active: root.urgent && !root.active
        sourceComponent: Component {
            WorkspaceUrgentFx { barActive: root.barActive }
        }
    }

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
        opacity: (1 - root._revealAmt) * root._dotFade * (root._hoverFx && !root.urgent
                 ? Math.min(1, root._dotAlpha + 0.18)
                 : root._dotAlpha) * root._pulseOpacity * ShellSettings.wsMarkerOpacity
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
