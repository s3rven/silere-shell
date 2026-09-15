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
    property color tint: Theme.error

    readonly property bool _interactive: root.enabled && !root.busy
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

    // the pinned widths keep the menu's button steady; max() only ever grows it, so a
    // longer label cannot clip against them
    width:  visible ? Math.max(root._armed ? root.armedWidth : root.restWidth,
                               _row.implicitWidth + 20) : 0
    height: Metrics.rowHeightFor(root.designHeight)
    radius: Theme.radiusControl
    antialiasing: true
    onVisibleChanged: if (!visible) root.disarm()
    onEnabledChanged: if (!enabled) root.disarm()
    onBusyChanged: if (busy) root.disarm()

    // mix, not withAlpha: the notification popup window is transparent, so an alpha tint
    // would let the desktop through where the menu's opaque backdrop hides it
    color: root._armed
        ? Theme.mix(Theme.menuControl, root.tint, _tap.pressed ? 0.28 : 0.16)
        : _tap.pressed ? Theme.mix(Theme.menuControl, root.tint, 0.20)
        : _hover.hovered ? Theme.mix(Theme.menuControl, Theme.subtext, 0.16) : Theme.menuControl

    opacity: root._interactive ? 1.0 : Theme.disabledOpacity

    OutlineBorder {
        radius: root.radius
        outlineWidth: root._armed ? 2 : 1
        outlineColor: root._armed
            ? Theme.withAlpha(root.tint, Theme.focusRingAlpha)
            : root.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
        ColorFade on outlineColor {}
    }

    MotionBehavior on width {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    ColorFade on color {}
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root._armed ? root.armedLabel : ""
    Accessible.focusable: root._interactive
    Accessible.onPressAction: root.request()

    HoverHandler {
        id: _hover
        enabled: root._interactive
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler { id: _tap; enabled: root._interactive; onTapped: root.request() }

    Row {
        id: _row
        anchors.centerIn: parent
        spacing: 4

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            text: root.glyph
            color: root._armed ? root.tint
                : _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.72)
            font.pixelSize: Settings.fontSize
            ColorFade on color {}
        }

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text: root._armed ? root.armedLabel : root.label
            color: root._armed ? root.tint
                : _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.text, 0.76)
            font.pixelSize: Settings.fontCaption
            font.weight: root._armed ? Font.DemiBold : Font.Normal
            ColorFade on color {}
        }
    }
}
