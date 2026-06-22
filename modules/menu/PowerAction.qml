import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string description: ""
    property color confirmColor: Theme.warning
    property bool confirm: false
    property bool armed: false
    property real _armProgress: 0

    signal triggered()

    height: parent ? parent.height : 44
    opacity: root.enabled ? 1.0 : 0.38

    Timer {
        id: _armTimer
        interval: 3000
        onTriggered: root.armed = false
    }
    NumberAnimation {
        id: _armCountdown
        target: root
        property: "_armProgress"
        from: 1.0
        to: 0.0
        duration: 3000
        easing.type: Easing.Linear
    }

    onArmedChanged: {
        if (!armed) {
            _armTimer.stop()
            _armCountdown.stop()
            _armProgress = 0
        }
    }
    onEnabledChanged: if (!root.enabled) root.disarm()

    function disarm(): void { root.armed = false }
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
    Accessible.description: root.armed ? "Press again to confirm" : root.description
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }

    HoverHandler { id: _hover; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: root.enabled; onTapped: root._activate() }

    Rectangle {
        anchors.fill: parent
        radius: 8
        antialiasing: true
        color: root.armed
            ? Theme.withAlpha(root.confirmColor, 0.14)
            : _hover.hovered && root.enabled
                ? Theme.withAlpha(root.confirm ? root.confirmColor : Theme.subtext, root.confirm ? 0.09 : 0.14)
                : Theme.withAlpha(Theme.subtext, 0.06)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? Theme.withAlpha(root.armed ? root.confirmColor : Theme.accent, 0.78)
            : root.armed
                ? Theme.withAlpha(root.confirmColor, 0.42)
                : Theme.withAlpha(Theme.subtext, 0.16)

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.glyph
                color: root.armed ? root.confirmColor
                    : root.confirm ? Theme.withAlpha(root.confirmColor, 0.88)
                    : (_hover.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.76))
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 3
                font.weight: root.armed ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.armed ? "Confirm" : root.label
                color: root.armed ? root.confirmColor : Theme.withAlpha(Theme.subtext, 0.62)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 3
                font.weight: root.armed ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    Canvas {
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        visible: root.armed

        property real progress: root._armProgress
        onProgressChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const p = root._armProgress
            if (p <= 0) return

            const o = 0.5
            const r = 7.5
            const w = width - 1.0
            const h = height - 1.0
            const arc = Math.PI / 2 * r
            const sH = w - 2 * r
            const sV = h - 2 * r
            let rem = p * (2*sH + 2*sV + 4*arc)

            ctx.strokeStyle = root.confirmColor
            ctx.lineWidth = 1.0
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(o + r, o)
            if (rem > 0) { const d = Math.min(rem, sH);  ctx.lineTo(o+r+d, o); rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(w+o-r, o+r, r, -Math.PI/2, -Math.PI/2+d/r, false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sV);  ctx.lineTo(w+o, o+r+d); rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(w+o-r, h+o-r, r, 0, d/r, false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sH);  ctx.lineTo(w+o-r-d, h+o); rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(o+r, h+o-r, r, Math.PI/2, Math.PI/2+d/r, false); rem -= d }
            if (rem > 0) { const d = Math.min(rem, sV);  ctx.lineTo(o, h+o-r-d); rem -= d }
            if (rem > 0) { const d = Math.min(rem, arc); ctx.arc(o+r, o+r, r, Math.PI, Math.PI+d/r, false) }
            ctx.stroke()
        }
    }
}
