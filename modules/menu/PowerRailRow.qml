pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property bool interactive: true
    property bool dangerous: false
    property bool confirm: false
    property bool armed: false
    property bool tintedGlyph: false
    property string confirmLabel: "Press again"
    property int confirmTimeout: 3000
    property color accentColor: Theme.accent

    signal triggered()

    readonly property bool _hot: root.enabled && root.interactive && (_hover.hovered)
    readonly property bool _showValue: root.value.length > 0 && !root.armed
    // the rail's width is fixed while its text grows, so at raised uiScale the value crowded
    // the label out; a clipped "Mod…" loses the row's identity where a clipped value still
    // reads, so the value yields first. 62 = the label's left offset plus the gap before it
    TextMetrics {
        id: _labelInk
        font.family:    Settings.font
        font.pixelSize: Settings.fontLabel
        font.weight:    root.armed ? Font.DemiBold : Font.Normal
        text:           root.armed ? root.confirmLabel : root.label
    }
    readonly property int _valueMaxW: Math.max(42, Math.min(86,
        Math.round(root.width * 0.52),
        root.width - 62 - Math.ceil(_labelInk.advanceWidth) - 1))
    property real _shift: root._hot || root.armed ? 0.5 : 0.0
    readonly property color _fg: root.armed
        ? Theme.text
        : root.dangerous
            ? Theme.mix(Theme.text, Theme.error, root._hot ? 0.18 : 0.08)
            : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.18), root._hot ? 0.94 : 0.78)
    readonly property color _glyphFg: root.armed
        ? Theme.error
        : root.tintedGlyph
            ? Theme.withAlpha(root.accentColor, root.interactive ? (root._hot ? 0.90 : 0.72) : 0.86)
            : root.dangerous
                ? Theme.withAlpha(Theme.error, root._hot ? 0.86 : 0.60)
                : Theme.withAlpha(Theme.subtext, root._hot ? 0.78 : 0.56)

    width: parent ? parent.width : implicitWidth
    height: Metrics.rowHeightFor(30)
    radius: Theme.radiusInline
    antialiasing: true
    opacity: root.enabled ? 1.0 : 0.38
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }
    color: root.armed
        ? Theme.withAlpha(Theme.error, 0.105)
        : root._hot ? Theme.withAlpha(Theme.text, 0.045) : "transparent"

    OutlineBorder {
        radius: root.radius
        outlineWidth: 2
        outlineColor: "transparent"
        ColorFade on outlineColor {}
    }

    function disarm(): void {
        root.armed = false
    }

    function activate(): void {
        if (!root.enabled || !root.interactive) return
        if (!root.confirm || root.armed) {
            // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
            if (root.armed && Date.now() - root._confirmStartedMs < Metrics.confirmGuardMs) return
            root.disarm()
            root.triggered()
        } else {
            root.armed = true
            _armTimer.restart()
        }
    }

    onEnabledChanged: if (!root.enabled) root.disarm()
    onInteractiveChanged: if (!root.interactive) root.disarm()
    onConfirmChanged: if (!root.confirm) root.disarm()

    onArmedChanged: {
        _confirmStartedMs = root.armed ? Date.now() : 0
        _confirmProgress = root.armed ? 1.0 : 0.0
    }

    Timer {
        id: _armTimer
        interval: root.confirmTimeout
        onTriggered: root.disarm()
    }

    property real _confirmProgress: 0.0
    property real _confirmStartedMs: 0

    // keep the confirmation countdown time-based so delayed frames never extend it
    Timer {
        interval: 33
        repeat: true
        triggeredOnStart: true
        running: root.armed && !ShellSettings.reduceMotion
        onTriggered: {
            const elapsed = Date.now() - root._confirmStartedMs
            root._confirmProgress = Math.max(0, 1 - elapsed / Math.max(1, root.confirmTimeout))
        }
    }

    PerimeterProgress {
        anchors.fill: parent
        // the ticker that drains this is a motion gate, so under reduce motion the ring
        // would sit full for the whole window and read as "nothing is expiring"
        visible: root.armed && !ShellSettings.reduceMotion
        inset:        1.0
        cornerRadius: root.radius
        progress:     root._confirmProgress
        trackColor:   Theme.menuControlLine
        arcColor:     Theme.withAlpha(Theme.error, 0.72)
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.interactive
        cursorShape: root.enabled && root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.enabled && root.interactive
        onTapped: root.activate()
    }

    ColorFade on color {}
    MotionBehavior on _shift {
        NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
    }

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root._glyphFg
        font.pixelSize: Settings.fontSize
        transform: Translate { x: root._shift }
        ColorFade on color {}
    }

    ShellText {
        id: _value
        visible: root._showValue
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root._valueMaxW)
        text: root.value
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        color: Theme.withAlpha(Theme.menuTextMuted, root._hot ? 0.84 : 0.66)
        font.pixelSize: Settings.fontCaption
        font.weight: Font.Medium
        ColorFade on color {}
    }

    ShellText {
        anchors.left: _glyph.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: root._showValue ? Math.round(_value.width + 20) : 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.armed ? root.confirmLabel : root.label
        elide: Text.ElideRight
        color: root._fg
        font.pixelSize: Settings.fontLabel
        font.weight: root.armed ? Font.DemiBold : Font.Normal
        transform: Translate { x: root._shift }
        ColorFade on color {}
    }
}
