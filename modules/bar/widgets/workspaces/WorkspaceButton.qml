pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"
import "../../../common"

Item {
    id: root

    required property int wsId
    required property bool isNew
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
    signal moveWindowRequested()
    signal anchorMenuRequested()
    signal quickActionsRequested()
    signal markerPulseRequested()
    signal hoverReported(int wsId, bool on)

    readonly property bool hovered: _hover.hovered
    readonly property bool _hoverFx: hovered && ShellSettings.barHoverHighlight
    // a slot with no workspace behind it collapses instead of being destroyed, so the
    // strip can grow and shrink without the row rebuilding under the motion
    readonly property bool present: wsId >= 0
    // an underline marker leaves the cell centre free, so the active workspace keeps its own content
    readonly property bool _blanked: active && markerCovers
    readonly property bool _showIcons: ShellSettings.wsShowAppIcons && !_blanked
        && !isNew && apps.length > 0

    width:  present ? cellWidth : 0
    height: rowHeight
    // the centred glyph is not clipped by a narrowing cell, so it has to be gone before
    // the cell is: the fade runs shorter than the collapse on purpose
    property real _presence: present ? 1 : 0
    MotionBehavior on _presence {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }
    visible: root.width > 0.5 || root._presence > 0.01

    function _motionAllowed(): bool {
        return root.barActive
            && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    }

    function _settleMotion(): void {
        _swapAnim.retire()
        _dropPulse.retire()
        _dotFadeOut.stop()
        _dotFadeIn.stop()
        root.clearMarkerPass()
        root._dotFade = root._blanked ? 0 : 1
    }

    MotionBehavior on width {
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: {
        _dotFade = _blanked ? 0 : 1
        _prevWsId = wsId
    }
    Component.onDestruction: if (root.hovered) root.hoverReported(root.wsId, false)

    // slots are index-keyed, so a workspace opening mid-strip renumbers every cell after
    // it. Without this the labels change between two frames with nothing to read as motion.
    property real _swapFade: 1
    property int _prevWsId: -1
    readonly property bool swapFading: _swapAnim.running
    onWsIdChanged: {
        const previous = root._prevWsId
        root._prevWsId = root.wsId
        // a fixed strip only renumbers on a page turn, which the whole row already fades;
        // an arrival or a departure is carried by the collapse
        if (previous < 0 || root.wsId < 0 || !root.initialized
                || !ShellSettings.wsDynamic || !root._motionAllowed()) {
            _swapAnim.retire()
            return
        }
        _swapAnim.restart()
    }

    BumpAnimation {
        id: _swapAnim
        target: root
        targetProperty: "_swapFade"
        peak: 0.25
        riseEasing: Easing.OutCubic
    }

    BumpAnimation {
        id: _dropPulse
        target: root
        targetProperty: "scale"
        peak: 1.12
    }

    // the menu is not a compositor feature, and this is the only pointer path into it:
    // gating it on live workspace data strands every setting when that data is absent
    function _activate(): void {
        if (!root.monitorReady) {
            root.anchorMenuRequested()
            return
        }
        if (root.active) {
            root.markerPulseRequested()
            root.anchorMenuRequested()
        } else {
            root.activateRequested()
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.isNew ? "New workspace" : "Workspace " + root.wsId
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
                root.moveWindowRequested()
                if (root._motionAllowed()) _dropPulse.restart()
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
        if (!root._motionAllowed()) { _dotFade = _blanked ? 0 : 1; return }
        _dotFadeOut.stop(); _dotFadeIn.stop()
        if (_blanked) _dotFadeOut.restart()
        else          _dotFadeIn.restart()
    }
    onActiveChanged: if (root.active) root.clearMarkerPass()
    onPagingChanged: if (root.paging) root.clearMarkerPass()
    onBarActiveChanged: if (!root.barActive) root._settleMotion()

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settleMotion()
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) root._settleMotion()
        }
    }

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
        opacity: (1 - root._markerPassCover) * root._presence * root._swapFade

        ShellText {
            anchors.centerIn: parent
            transform: Translate { x: root._shakeX }
            text:    root.isNew ? "󰐕" : root.wsId
            opacity: (root.isNew
                    ? 1
                    : root._showIcons
                    ? root._revealAmt
                    : Math.max(ShellSettings.wsShowNumbers ? 1 : 0, root._revealAmt))
                * (root._blanked ? 0 : 1) * root._pulseOpacity * ShellSettings.wsMarkerOpacity
            scale:   root._blanked ? 0.6 : (root._hoverFx ? 1.12 : 1)
            color:   root.urgent
                ? Theme.warning
                : root.active
                ? Theme.accent
                : root.isNew
                ? (root._hoverFx ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.5))
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
            visible: !ShellSettings.wsShowNumbers && !root._showIcons && !root.isNew
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
