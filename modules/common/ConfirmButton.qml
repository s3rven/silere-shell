pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string armedLabel: "Confirm?"
    property int restWidth: 68
    property int armedWidth: 92
    property int designHeight: 30
    property bool busy: false
    property bool shown: true
    property color tint: Theme.error

    readonly property bool _interactive: root.enabled && root.shown && root.visible && !root.busy
    readonly property bool armed: root._armed
    readonly property bool hovered: _hover.hovered

    signal confirmed()

    property bool _armed: false
    property real _armedAtMs: 0

    function request(): void {
        if (!root._interactive) return
        if (root._armed) {
            // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
            if (Date.now() - root._armedAtMs < Metrics.confirmGuardMs) return
            // the confirm usually hides the button; holding the armed face stops it morphing back while it fades
            root._holdArmed = true
            _holdTimer.restart()
            root.disarm()
            root.confirmed()
            return
        }
        root._armed = true
        root._armedAtMs = Date.now()
        _armTimer.restart()
    }

    function disarm(): void {
        root._armed = false
        _armTimer.stop()
    }

    Timer { id: _armTimer; interval: 3000; onTriggered: root._armed = false }

    property bool _holdArmed: false
    Timer { id: _holdTimer; interval: Motion.normal + Motion.ms(160); onTriggered: root._holdArmed = false }

    readonly property bool _armedFace: root._armed || root._holdArmed
    property real _armT: root._armedFace ? 1 : 0
    property real _reveal: root.shown ? 1 : 0
    property real _dim: root._interactive ? 1.0 : Theme.disabledOpacity
    // the pinned widths keep the menu's button steady; max() only ever grows it, so a
    // longer label cannot clip against them
    property real _restW: Math.max(root.restWidth, _restRow.implicitWidth + 20)
    property real _armedW: Math.max(root.armedWidth, _armedRow.implicitWidth + 20)

    // no Behavior on width: it would grow from 0 every time the button is shown
    width:  visible ? root._restW + (root._armedW - root._restW) * root._armT : 0
    height: Metrics.rowHeightFor(root.designHeight)
    radius: Theme.radiusControl
    antialiasing: true
    clip: root._armT > 0 && root._armT < 1
    visible: root._reveal > 0.001
    onVisibleChanged: if (!visible) root.disarm()
    onShownChanged: if (!shown) root.disarm()
    onEnabledChanged: if (!enabled) root.disarm()
    onBusyChanged: if (busy) root.disarm()

    // mix, not withAlpha: the notification popup window is transparent, so an alpha tint
    // would let the desktop through where the menu's opaque backdrop hides it
    color: root._armedFace
        ? Theme.mix(Theme.menuControl, root.tint, _tap.pressed ? 0.28 : 0.16)
        : _tap.pressed ? Theme.mix(Theme.menuControl, root.tint, 0.20)
        : _hover.hovered ? Theme.mix(Theme.menuControl, Theme.subtext, 0.16) : Theme.menuControl

    opacity: root._reveal * root._dim

    OutlineBorder {
        radius: root.radius
        outlineWidth: root._armedFace ? 2 : 1
        outlineColor: root._armedFace
            ? Theme.withAlpha(root.tint, Theme.focusRingAlpha)
            : root.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
        ColorFade on outlineColor {}
    }

    MotionBehavior on _armT {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
    MotionBehavior on _reveal {
        id: _revealB
        NumberAnimation {
            duration: _revealB.targetValue > 0.5 ? Motion.normal : Motion.fast
            easing.type: _revealB.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
        }
    }
    MotionBehavior on _restW {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    MotionBehavior on _armedW {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    MotionBehavior on _dim {NumberAnimation { duration: Motion.fast } }
    ColorFade on color {}

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root._armed ? root.armedLabel : ""
    Accessible.focusable: root._interactive
    Accessible.onPressAction: root.request()

    HoverHandler {
        id: _hover
        enabled: root._interactive && root.shown
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler { id: _tap; enabled: root._interactive && root.shown; onTapped: root.request() }

    // two faces crossfaded, so the label never swaps while the width is still moving
    Row {
        id: _restRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -4 * root._armT
        spacing: 4
        opacity: 1 - root._armT
        visible: opacity > 0.001

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            text: root.glyph
            color: _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.72)
            font.pixelSize: Settings.fontSize
            ColorFade on color {}
        }

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.text, 0.76)
            font.pixelSize: Settings.fontCaption
            ColorFade on color {}
        }
    }

    Row {
        id: _armedRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 4 * (1 - root._armT)
        spacing: 4
        opacity: root._armT
        visible: opacity > 0.001

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            text: root.glyph
            color: root.tint
            font.pixelSize: Settings.fontSize
        }

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.armedLabel
            color: root.tint
            font.pixelSize: Settings.fontCaption
            font.weight: Font.DemiBold
        }
    }
}
