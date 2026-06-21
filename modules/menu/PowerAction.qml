import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property color confirmColor: Theme.warning
    property bool confirm: false
    property bool armed: false

    property real _armProgress: 0

    signal triggered()

    height: parent ? parent.height : 44

    Timer {
        id: _armTimer
        interval: 3000
        onTriggered: root.armed = false
    }

    NumberAnimation {
        id: _armCountdown
        target: root; property: "_armProgress"
        from: 1.0; to: 0.0
        duration: 3000; easing.type: Easing.Linear
    }

    onArmedChanged: {
        if (!armed) {
            _armTimer.stop()
            _armCountdown.stop()
            _armProgress = 0
        }
    }

    function disarm(): void {
        root.armed = false
    }

    function _activate(): void {
        if (!root.enabled) return
        if (!root.confirm) {
            root.triggered()
        } else if (!root.armed) {
            root.armed = true
            _armTimer.restart()
            if (!ShellSettings.reduceMotion) _armCountdown.restart()
        } else {
            root.triggered()
        }
    }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.confirm && !root.armed ? "Requires confirmation" : ""
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }

    HoverHandler {
        id: _hover
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.enabled
        onTapped: root._activate()
    }

    // Gentle lift on hover so the strip feels responsive; destructive actions
    // (confirm) read warm even before you arm them, so Reboot/Power never look
    // like a harmless tap.
    readonly property bool _danger: root.confirm && _hover.hovered && root.enabled && !root.armed

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        antialiasing: true
        opacity: root.enabled ? 1.0 : 0.45
        scale: _hover.hovered && root.enabled && !ShellSettings.reduceMotion ? 1.04 : 1.0
        color: {
            if (root.armed) return _hover.hovered
                ? Theme.withAlpha(root.confirmColor, 0.22)
                : Theme.withAlpha(root.confirmColor, 0.12)
            if (root._danger) return Theme.withAlpha(root.confirmColor, 0.12)
            return _hover.hovered && root.enabled
                ? Theme.withAlpha(Theme.subtext, 0.22)
                : Theme.withAlpha(Theme.subtext, 0.10)
        }
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? Theme.withAlpha(root.armed ? root.confirmColor : Theme.accent, 0.82)
            : root.armed
            ? Theme.withAlpha(root.confirmColor, 0.45)
            : root._danger
                ? Theme.withAlpha(root.confirmColor, 0.30)
                : Theme.withAlpha(Theme.subtext, 0.22)

        Behavior on color        { ColorAnimation { duration: Motion.normal } }
        Behavior on border.color { ColorAnimation { duration: Motion.normal } }
        Behavior on scale        { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        Column {
            anchors.centerIn: parent
            spacing: 3

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.glyph
                color: root.armed ? root.confirmColor
                     : root._danger ? Theme.withAlpha(root.confirmColor, 0.95)
                     : (_hover.hovered && root.enabled ? Theme.text : Theme.withAlpha(Theme.text, 0.78))
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 5
                font.weight: root.armed ? Font.Bold : Font.Normal
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.normal } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.armed ? (root.label + "?") : root.label
                color: root.armed ? root.confirmColor
                     : root._danger ? Theme.withAlpha(root.confirmColor, 0.7)
                     : Theme.withAlpha(Theme.subtext, 0.52)
                font.family: Settings.font; font.pixelSize: Settings.fontSize - 3
                renderType: Text.NativeRendering
                visible: root.enabled && root.label.length > 0
                Behavior on color { ColorAnimation { duration: Motion.normal } }
            }
        }
    }

    Canvas {
        id: _borderCanvas
        anchors.fill: parent
        renderTarget:   Canvas.Image
        renderStrategy: Canvas.Threaded
        visible: root.armed

        property real progress: root._armProgress
        onProgressChanged: requestPaint()
        onVisibleChanged:  if (visible) requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const p = root._armProgress
            if (p <= 0) return

            const o   = 0.5
            const r   = Math.max(0.5, Theme.radiusControl - 0.5)
            const w   = width  - 1.0  // right edge center-line  (width  - 2*o)
            const h   = height - 1.0  // bottom edge center-line (height - 2*o)
            const arc = Math.PI / 2 * r
            const sH  = w - 2 * r
            const sV  = h - 2 * r
            let   rem = p * (2*sH + 2*sV + 4*arc)

            ctx.strokeStyle = root.confirmColor
            ctx.lineWidth   = 1.0
            ctx.lineCap     = "round"
            ctx.beginPath()
            ctx.moveTo(o + r, o)

            if (rem > 0) { const d = Math.min(rem, sH);  ctx.lineTo(o+r+d, o);                                            rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(w+o-r, o+r,   r, -Math.PI/2, -Math.PI/2 + d/r, false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sV);  ctx.lineTo(w+o, o+r+d);                                          rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(w+o-r, h+o-r, r,  0,          d/r,             false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sH);  ctx.lineTo(w+o-r-d, h+o);                                        rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(o+r,   h+o-r, r,  Math.PI/2,  Math.PI/2 + d/r, false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sV);  ctx.lineTo(o, h+o-r-d);                                          rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(o+r,   o+r,   r,  Math.PI,    Math.PI + d/r,   false) }

            ctx.stroke()
        }
    }
}
