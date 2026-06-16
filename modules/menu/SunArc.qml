pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// Dashboard sun-path: bell arc with the sun's current position + sunrise/sunset.
Rectangle {
    id: root

    width:  parent ? parent.width : 0
    implicitHeight: 132
    height: implicitHeight
    radius: 12
    antialiasing: true
    color: Theme.mix(Theme.surface, Theme.subtext, 0.06)
    border.width: 1
    border.color: Theme.withAlpha(Theme.subtext, 0.10)

    readonly property bool _isDay: NightLight.isDaytime

    // Sun colour warms toward the horizon (golden hour), brightens toward noon.
    readonly property real _elev: {
        const t = Math.max(0, Math.min(1, animProg))
        return Math.pow((1 - Math.cos(2 * Math.PI * t)) / 2, 0.72)
    }
    readonly property color _sunDyn: _elev < 0.5
        ? Theme.mix(Theme.mix(Theme.warning, Theme.error, 0.35), Theme.warning, _elev * 2)
        : Theme.mix(Theme.warning, Theme.text, (_elev - 0.5) * 0.7)

    // False while hidden → zero canvas work until on screen.
    property bool shown: true

    property real animProg: 0
    onAnimProgChanged: _cv.requestPaint()

    NumberAnimation {
        id: _sweep
        target: root; property: "animProg"
        from: 0; duration: Motion.ms(860); easing.type: Easing.OutCubic
    }
    function _playSweep(): void {
        if (!root.shown) return
        const target = Math.max(0, NightLight.dayProgress)
        if (ShellSettings.reduceMotion) { _sweep.stop(); root.animProg = target; return }
        _sweep.stop(); _sweep.to = target; _sweep.restart()
    }
    Component.onCompleted: Qt.callLater(root._playSweep)
    onShownChanged: if (shown) Qt.callLater(root._playSweep)   // sweep in when it appears
    Connections {
        target: MenuState
        function onOpenChanged() { if (root.shown && MenuState.open) Qt.callLater(root._playSweep) }
    }
    Connections {
        target: NightLight
        // per-minute drift; skip while hidden/closed or mid-sweep
        function onDayProgressChanged() {
            if (root.shown && MenuState.open && !_sweep.running) root.animProg = Math.max(0, NightLight.dayProgress)
        }
    }

    Text {
        x: 14; y: 11
        text: root._isDay ? "Daylight" : "Night"
        color: Theme.text
        font.family: Settings.font
        font.pixelSize: Settings.fontSize
        renderType: Text.NativeRendering
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 14
        y: 12
        text: NightLight.phaseLabel
        color: Theme.withAlpha(Theme.subtext, 0.85)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 1
        renderType: Text.NativeRendering
    }

    Canvas {
        id: _cv
        anchors.left: parent.left;     anchors.leftMargin: 2
        anchors.right: parent.right;   anchors.rightMargin: 2
        anchors.top: parent.top;       anchors.topMargin: 33
        anchors.bottom: parent.bottom; anchors.bottomMargin: 20
        renderTarget:   Canvas.Image
        renderStrategy: Canvas.Threaded

        // colour bindings so a theme change repaints
        readonly property color horizonColor: Theme.withAlpha(Theme.subtext, 0.22)
        readonly property color arcColor:     Theme.withAlpha(Theme.subtext, 0.28)
        readonly property color sunColor:     Theme.warning
        readonly property color dynSun:       root._sunDyn
        readonly property color dynGlow:      Theme.withAlpha(root._sunDyn, 0.45)
        readonly property color sunCore:      Theme.withAlpha(Theme.text, 0.9)
        readonly property color fillTop:      Theme.withAlpha(Theme.warning, 0.02)
        readonly property color fillBot:      Theme.withAlpha(Theme.warning, 0.20)
        readonly property color strokePeak:   Theme.mix(Theme.warning, Theme.text, 0.45)
        readonly property color moonColor:    Theme.withAlpha(Theme.subtext, 0.55)
        readonly property color cardColor:    root.color
        readonly property bool  isDay:        NightLight.isDaytime
        readonly property real  nightProg:    NightLight.nightProgress
        onNightProgChanged: if (!isDay) requestPaint()

        // Gradient cache — rebuilt only when dimensions or colours change.
        property var  _fg: null; property real _fgH: -1
        property color _fgTop: "transparent"; property color _fgBot: "transparent"
        property var  _sg: null; property real _sgW: -1
        property color _sgSun: "transparent"; property color _sgPeak: "transparent"

        onHorizonColorChanged: requestPaint()
        onArcColorChanged:     requestPaint()
        onSunColorChanged:     requestPaint()
        onIsDayChanged:        requestPaint()
        onWidthChanged:        requestPaint()
        onHeightChanged:       requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            if (w <= 0 || h <= 0) return

            const padX  = 22
            // Horizon at 63% of canvas height: enough room above for sun glow (14px
            // headroom clears the 12px radius), and below for the underground moon arc.
            const baseY = Math.round(h * 0.63)
            const amp   = baseY - 14
            const N     = 40

            const xAt    = (t) => padX + t * (w - 2 * padX)
            const hAt    = (t) => Math.pow((1 - Math.cos(2 * Math.PI * t)) / 2, 0.72)
            const yAt    = (t) => baseY - hAt(t) * amp

            // horizon line
            ctx.strokeStyle = horizonColor
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(padX, baseY); ctx.lineTo(w - padX, baseY); ctx.stroke()

            // full sun arc (faint gray guide, always drawn)
            ctx.strokeStyle = arcColor
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.beginPath()
            for (let i = 0; i <= N; i++) { const t = i / N; i ? ctx.lineTo(xAt(t), yAt(t)) : ctx.moveTo(xAt(t), yAt(t)) }
            ctx.stroke()

            if (!isDay) {
                // Underground moon arc: reversed left↔right so it starts at the
                // sunset side and ends at the sunrise side, mirroring how the sun
                // would continue underground after setting.
                const moonAmp  = Math.round((h - baseY) * 0.78)
                const xMoonAt  = (t) => xAt(1 - t)
                const yMoonAt  = (t) => baseY + hAt(t) * moonAmp

                ctx.strokeStyle = horizonColor
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.setLineDash([4, 3])
                ctx.beginPath()
                for (let i = 0; i <= N; i++) { const t = i/N; i ? ctx.lineTo(xMoonAt(t), yMoonAt(t)) : ctx.moveTo(xMoonAt(t), yMoonAt(t)) }
                ctx.stroke()
                ctx.setLineDash([])

                const np = Math.max(0, Math.min(1, nightProg))
                const mx = xMoonAt(np), my = yMoonAt(np)
                ctx.fillStyle = moonColor
                ctx.beginPath(); ctx.arc(mx, my, 6, 0, 2 * Math.PI); ctx.fill()
                ctx.fillStyle = cardColor
                ctx.beginPath(); ctx.arc(mx + 3.5, my - 2, 6.5, 0, 2 * Math.PI); ctx.fill()
                return
            }

            const p = Math.max(0, Math.min(1, root.animProg))
            const M = Math.max(2, Math.ceil(N * p))

            // fill gradient — cached by canvas height + colour inputs
            if (!_fg || _fgH !== h || _fgTop !== fillTop || _fgBot !== fillBot) {
                _fg = ctx.createLinearGradient(0, baseY - amp, 0, baseY)
                _fg.addColorStop(0, fillTop); _fg.addColorStop(1, fillBot)
                _fgH = h; _fgTop = fillTop; _fgBot = fillBot
            }
            ctx.beginPath()
            ctx.moveTo(xAt(0), baseY)
            for (let i = 0; i <= M; i++) { const t = p * i / M; ctx.lineTo(xAt(t), yAt(t)) }
            ctx.lineTo(xAt(p), baseY)
            ctx.closePath()
            ctx.fillStyle = _fg; ctx.fill()

            // stroke gradient — cached by canvas width + colour inputs
            if (!_sg || _sgW !== w || _sgSun !== sunColor || _sgPeak !== strokePeak) {
                _sg = ctx.createLinearGradient(xAt(0), 0, xAt(1), 0)
                _sg.addColorStop(0.0, sunColor)
                _sg.addColorStop(0.5, strokePeak)
                _sg.addColorStop(1.0, sunColor)
                _sgW = w; _sgSun = sunColor; _sgPeak = strokePeak
            }
            ctx.strokeStyle = _sg
            ctx.lineWidth = 2.5
            ctx.lineCap = "round"
            ctx.beginPath()
            for (let i = 0; i <= M; i++) { const t = p * i / M; i ? ctx.lineTo(xAt(t), yAt(t)) : ctx.moveTo(xAt(t), yAt(t)) }
            ctx.stroke()

            // sun disc + glow (radial gradient can't be cached — position moves each frame)
            const sx = xAt(p), sy = yAt(p)
            const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, 12)
            g.addColorStop(0, dynGlow); g.addColorStop(1, "transparent")
            ctx.fillStyle = g;       ctx.beginPath(); ctx.arc(sx, sy, 12, 0, 2 * Math.PI); ctx.fill()
            ctx.fillStyle = dynSun;  ctx.beginPath(); ctx.arc(sx, sy, 4.5, 0, 2 * Math.PI); ctx.fill()
            ctx.fillStyle = sunCore; ctx.beginPath(); ctx.arc(sx, sy, 2, 0, 2 * Math.PI); ctx.fill()
        }
    }

    // sunrise (bottom-left) / sunset (bottom-right)
    Row {
        x: 14
        anchors.bottom: parent.bottom; anchors.bottomMargin: 7
        spacing: 5
        Text {
            text: "󰖜"; color: Theme.withAlpha(Theme.subtext, 0.8)
            font.family: Settings.font; font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: NightLight.sunriseLabel; color: Theme.subtext
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.bottom: parent.bottom; anchors.bottomMargin: 7
        spacing: 5
        Text {
            text: NightLight.sunsetLabel; color: Theme.subtext
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: "󰖛"; color: Theme.withAlpha(Theme.subtext, 0.8)
            font.family: Settings.font; font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
