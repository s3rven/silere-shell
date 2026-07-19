pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

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

    readonly property bool _hot: root.enabled && root.interactive && (_hover.hovered || root.activeFocus)
    readonly property bool _showValue: root.value.length > 0 && !root.armed
    readonly property int _valueMaxW: Math.max(42, Math.min(86, Math.round(root.width * 0.52)))
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
    height: 30
    radius: 8
    antialiasing: true
    opacity: root.enabled ? 1.0 : 0.38
    color: root.armed
        ? Theme.withAlpha(Theme.error, 0.105)
        : root._hot ? Theme.withAlpha(Theme.text, 0.045) : "transparent"
    border.width: root.activeFocus && !root.armed ? 1 : 0
    border.color: root.armed ? Theme.withAlpha(Theme.error, 0.54)
        : root.dangerous ? Theme.withAlpha(Theme.error, 0.34)
        : Theme.menuControlLineHot
    activeFocusOnTab: root.enabled && root.interactive

    Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.armed ? root.label + ", press again to confirm" : root.label
    Accessible.description: root.value

    function disarm(): void {
        root.armed = false
    }

    function activate(): void {
        if (!root.enabled || !root.interactive) return
        if (!root.confirm || root.armed) {
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

    // Confirmation uses the notification-style perimeter countdown instead of a
    // detached fuse line, keeping the warning attached to the whole action.
    property real _confirmProgress: 0.0
    property real _confirmStartedMs: 0

    // 30Hz, not a NumberAnimation: each tick is a threaded Canvas texture upload
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

    Canvas {
        id: _confirmOutline
        anchors.fill: parent
        visible: root.armed
        antialiasing: true
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        property real progress: root._confirmProgress

        function outline(ctx, inset, radius) {
            const x = inset
            const y = inset
            const w = width - inset * 2
            const h = height - inset * 2
            const r = Math.max(0.5, Math.min(radius, Math.min(w, h) / 2))
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.arc(x + w - r, y + r, r, -Math.PI / 2, 0)
            ctx.lineTo(x + w, y + h - r)
            ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2)
            ctx.lineTo(x + r, y + h)
            ctx.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI)
            ctx.lineTo(x, y + r)
            ctx.arc(x + r, y + r, r, Math.PI, 3 * Math.PI / 2)
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return

            const inset = 1.0
            const radius = Math.max(0.5, root.radius - inset)
            const w = width - inset * 2
            const h = height - inset * 2
            const sx = Math.max(0, w - 2 * radius)
            const sy = Math.max(0, h - 2 * radius)
            const arc = Math.PI / 2 * radius

            outline(ctx, inset, radius)
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.menuControlLine
            ctx.stroke()

            let remaining = Math.max(0, Math.min(1, progress)) * (2 * sx + 2 * sy + 4 * arc)
            if (remaining <= 0) return

            ctx.beginPath()
            ctx.moveTo(inset + radius, inset)
            let segment = Math.min(remaining, sx)
            ctx.lineTo(inset + radius + segment, inset)
            remaining -= segment
            if (remaining > 0) { segment = Math.min(remaining, arc); ctx.arc(inset + w - radius, inset + radius, radius, -Math.PI / 2, -Math.PI / 2 + segment / radius); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, sy); ctx.lineTo(inset + w, inset + radius + segment); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, arc); ctx.arc(inset + w - radius, inset + h - radius, radius, 0, segment / radius); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, sx); ctx.lineTo(inset + w - radius - segment, inset + h); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, arc); ctx.arc(inset + radius, inset + h - radius, radius, Math.PI / 2, Math.PI / 2 + segment / radius); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, sy); ctx.lineTo(inset, inset + h - radius - segment); remaining -= segment }
            if (remaining > 0) { segment = Math.min(remaining, arc); ctx.arc(inset + radius, inset + radius, radius, Math.PI, Math.PI + segment / radius) }
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            ctx.strokeStyle = Theme.withAlpha(Theme.error, 0.72)
            ctx.stroke()
        }

        onVisibleChanged: requestPaint()
        onWidthChanged: if (visible) requestPaint()
        onHeightChanged: if (visible) requestPaint()
        onProgressChanged: if (visible) requestPaint()
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

    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    // armed rows eat the first Escape as a disarm; unarmed rows let it fall through to close the rail
    Keys.onEscapePressed: event => {
        if (root.armed) { root.disarm(); event.accepted = true }
        else event.accepted = false
    }

    Behavior on color {
        enabled: !ShellSettings.reduceMotion
        ColorAnimation { duration: Motion.fast }
    }
    Behavior on border.color {
        enabled: !ShellSettings.reduceMotion
        ColorAnimation { duration: Motion.fast }
    }
    Behavior on _shift {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
    }

    Text {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        width: 19
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root._glyphFg
        font.family: Settings.font
        font.pixelSize: Settings.fontSize
        renderType: Text.NativeRendering
        transform: Translate { x: root._shift }
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Text {
        id: _value
        visible: root._showValue
        anchors.right: parent.right
        anchors.rightMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root._valueMaxW)
        text: root.value
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        color: Theme.withAlpha(Theme.menuTextMuted, root._hot ? 0.84 : 0.66)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 2
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Text {
        anchors.left: _glyph.right
        anchors.leftMargin: 9
        anchors.right: parent.right
        anchors.rightMargin: root._showValue ? Math.round(_value.width + 19) : 11
        anchors.verticalCenter: parent.verticalCenter
        text: root.armed ? root.confirmLabel : root.label
        elide: Text.ElideRight
        color: root._fg
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 1
        font.weight: root.armed ? Font.DemiBold : Font.Normal
        renderType: Text.NativeRendering
        transform: Translate { x: root._shift }
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }
}
