pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    width:  parent ? parent.width : 0
    implicitHeight: 132
    height: implicitHeight

    property bool shown: true

    readonly property bool _isDay: NightLight.isDaytime
    readonly property real _half: Math.max(0, Math.min(12,
        (NightLight.sunsetHour - NightLight.sunriseHour) / 2))
    readonly property bool _crosses: _half > 0 && _half < 12
    readonly property real _t0: 0.5 - (_isDay ? _half : 12 - _half) / 24

    property real animProg: 0
    onAnimProgChanged: if (_cvLoader.item) _cvLoader.item.requestPaint()

    NumberAnimation {
        id: _sweep
        target: root; property: "animProg"
        from: 0; to: 1; duration: Motion.ms(860); easing.type: Easing.OutCubic
    }
    function _playSweep(): void {
        if (!root.shown) return
        _sweep.stop()
        if (ShellSettings.reduceMotion) { root.animProg = 1; return }
        _sweep.restart()
    }
    Component.onCompleted: Qt.callLater(root._playSweep)
    onShownChanged: {
        if (shown) Qt.callLater(root._playSweep)
        else       _sweep.stop()
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (root.shown && MenuState.open) Qt.callLater(root._playSweep) }
    }

    ShellText {
        x: 14; y: 11
        text: root._isDay ? "Daylight" : "Night"
        color: Theme.text
        font.pixelSize: Settings.fontSize
    }
    ShellText {
        anchors.right: parent.right; anchors.rightMargin: 14
        y: 12
        text: NightLight.phaseLabel
        color: Theme.withAlpha(Theme.subtext, 0.85)
        font.pixelSize: Settings.fontLabel
    }

    Loader {
        id: _cvLoader
        anchors.fill: parent
        // the buffer is the cost, not the paint — drop the canvas entirely while hidden
        active: root.shown
        sourceComponent: Component {
            Canvas {
                id: _cv
                anchors.left: parent.left;     anchors.leftMargin: 2
                anchors.right: parent.right;   anchors.rightMargin: 2
                anchors.top: parent.top;       anchors.topMargin: 33
                anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                renderTarget:   Canvas.Image
                renderStrategy: Canvas.Threaded

                readonly property real padX: 18
                readonly property color horizonColor: Theme.withAlpha(Theme.subtext, 0.22)
                readonly property color arcColor:     Theme.withAlpha(Theme.subtext, 0.30)
                readonly property color tailColor:    Theme.withAlpha(Theme.subtext, 0.12)
                readonly property color sunColor:     Theme.warning
                readonly property color sunCore:      Theme.withAlpha(Theme.text, 0.9)
                readonly property color strokePeak:   Theme.mix(Theme.warning, Theme.text, 0.45)
                readonly property color fillTop:      Theme.withAlpha(Theme.warning, 0.02)
                readonly property color fillBot:      Theme.withAlpha(Theme.warning, 0.20)
                readonly property color nightStroke:  Theme.withAlpha(Theme.subtext, 0.50)
                readonly property color nightFillTop: Theme.withAlpha(Theme.subtext, 0.14)
                readonly property color nightFillBot: Theme.withAlpha(Theme.subtext, 0.03)
                readonly property color nightDot:     Theme.withAlpha(Theme.text, 0.62)
                readonly property color nightGlow:    Theme.withAlpha(Theme.subtext, 0.20)
                readonly property bool  isDay:        root._isDay
                readonly property real  nowHour:      NightLight.nowHour
                readonly property real  riseHour:     NightLight.sunriseHour
                readonly property real  setHour:      NightLight.sunsetHour

                property var _fg: null; property string _fgKey: ""
                property var _sg: null; property string _sgKey: ""

                onHorizonColorChanged: requestPaint()
                onArcColorChanged:     requestPaint()
                onSunColorChanged:     requestPaint()
                onIsDayChanged:        requestPaint()
                onRiseHourChanged:     requestPaint()
                onSetHourChanged:      requestPaint()
                onNowHourChanged:      if (root.shown && MenuState.open) requestPaint()
                onWidthChanged:        requestPaint()
                onHeightChanged:       requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const w = width, h = height
                    if (w <= 0 || h <= 0) return

                    const day   = isDay
                    const half  = root._half
                    const noon  = (riseHour + setHour) / 2
                    const centre = day ? noon : noon + 12
                    // cos(hour angle) minus its value at the horizon: positive exactly between sunrise and sunset
                    const c0    = Math.cos(Math.PI * half / 12)
                    const upMax = Math.max(0.001, 1 - c0)
                    const dnMax = Math.max(0.001, 1 + c0)
                    const baseY = Math.round(h * (day ? 0.64 : 0.36))
                    const ampUp = day ? baseY - 8 : baseY - 6
                    const ampDn = day ? h - baseY - 6 : h - baseY - 8
                    const N     = 96

                    const xAt = (t) => padX + t * (w - 2 * padX)
                    const vAt = (t) => Math.cos(Math.PI * (centre - 12 + 24 * t - noon) / 12) - c0
                    const yAt = (t) => {
                        const v = vAt(t)
                        return v >= 0 ? baseY - v / upMax * ampUp : baseY - v / dnMax * ampDn
                    }
                    const trace = (a, b, n) => {
                        for (let i = 0; i <= n; i++) {
                            const t = a + (b - a) * i / n
                            i ? ctx.lineTo(xAt(t), yAt(t)) : ctx.moveTo(xAt(t), yAt(t))
                        }
                    }

                    const t0 = root._t0, t1 = 1 - t0
                    const tNow = Math.max(t0, Math.min(t1,
                        ((((nowHour - centre + 12) % 24) + 24) % 24) / 24))
                    const tMark = t0 + (tNow - t0) * Math.max(0, Math.min(1, root.animProg))
                    const M = Math.max(2, Math.ceil(N * (tMark - t0)))

                    ctx.lineCap = "round"
                    ctx.strokeStyle = horizonColor
                    ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(padX, baseY); ctx.lineTo(w - padX, baseY); ctx.stroke()

                    ctx.strokeStyle = tailColor
                    ctx.lineWidth = 1.5
                    ctx.beginPath(); trace(0, 1, N); ctx.stroke()

                    ctx.strokeStyle = arcColor
                    ctx.lineWidth = 2
                    ctx.beginPath(); trace(t0, t1, Math.ceil(N * (t1 - t0))); ctx.stroke()

                    if (tMark > t0) {
                        const fKey = [day, h, baseY, fillTop, fillBot, nightFillTop, nightFillBot].join()
                        if (!_fg || _fgKey !== fKey) {
                            _fg = day ? ctx.createLinearGradient(0, baseY - ampUp, 0, baseY)
                                      : ctx.createLinearGradient(0, baseY, 0, baseY + ampDn)
                            _fg.addColorStop(0, day ? fillTop : nightFillTop)
                            _fg.addColorStop(1, day ? fillBot : nightFillBot)
                            _fgKey = fKey
                        }
                        ctx.beginPath()
                        ctx.moveTo(xAt(t0), baseY)
                        for (let i = 0; i <= M; i++) { const t = t0 + (tMark - t0) * i / M; ctx.lineTo(xAt(t), yAt(t)) }
                        ctx.lineTo(xAt(tMark), baseY)
                        ctx.closePath()
                        ctx.fillStyle = _fg; ctx.fill()

                        if (day) {
                            const sKey = [w, t0, sunColor, strokePeak].join()
                            if (!_sg || _sgKey !== sKey) {
                                _sg = ctx.createLinearGradient(xAt(t0), 0, xAt(t1), 0)
                                _sg.addColorStop(0.0, sunColor)
                                _sg.addColorStop(0.5, strokePeak)
                                _sg.addColorStop(1.0, sunColor)
                                _sgKey = sKey
                            }
                        }
                        ctx.strokeStyle = day ? _sg : nightStroke
                        ctx.lineWidth = 2.5
                        ctx.beginPath(); trace(t0, tMark, M); ctx.stroke()
                    }

                    const sx = xAt(tMark), sy = yAt(tMark)
                    const lift = Math.max(0, Math.min(1, vAt(tMark) / upMax))
                    const sun = !day ? nightDot
                        : lift < 0.5 ? Theme.mix(Theme.mix(Theme.warning, Theme.error, 0.35), Theme.warning, lift * 2)
                        : Theme.mix(Theme.warning, Theme.text, (lift - 0.5) * 0.7)
                    const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, 12)
                    g.addColorStop(0, day ? Theme.withAlpha(sun, 0.45) : nightGlow)
                    g.addColorStop(1, "transparent")
                    ctx.fillStyle = g;   ctx.beginPath(); ctx.arc(sx, sy, 12, 0, 2 * Math.PI); ctx.fill()
                    ctx.fillStyle = sun; ctx.beginPath(); ctx.arc(sx, sy, day ? 4.5 : 3.5, 0, 2 * Math.PI); ctx.fill()
                    if (day) {
                        ctx.fillStyle = sunCore
                        ctx.beginPath(); ctx.arc(sx, sy, 2, 0, 2 * Math.PI); ctx.fill()
                    }
                }
            }
        }
    }

    // inline components cannot reach root, so the span arrives as properties
    component EventLabel: Row {
        id: _label
        property string glyph: ""
        property string time: ""
        property real centreX: 0
        property real areaWidth: 0
        spacing: 5
        x: Math.round(Math.max(14, Math.min(areaWidth - 14 - width, centreX - width / 2)))
        anchors.bottom: parent.bottom; anchors.bottomMargin: 7
        ShellText {
            text: _label.glyph; color: Theme.withAlpha(Theme.subtext, 0.8)
            font.pixelSize: Settings.fontSize
            anchors.verticalCenter: parent.verticalCenter
        }
        ShellText {
            text: _label.time; color: Theme.subtext
            font.pixelSize: Settings.fontLabel
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    readonly property real _spanX: 2 + 18
    readonly property real _spanW: Math.max(0, width - 4 - 36)
    EventLabel {
        glyph: root._isDay ? "󰖜" : "󰖛"
        time: root._isDay ? NightLight.sunriseLabel : NightLight.sunsetLabel
        centreX: root._spanX + root._t0 * root._spanW
        areaWidth: root.width
        visible: root._crosses
    }
    EventLabel {
        glyph: root._isDay ? "󰖛" : "󰖜"
        time: root._isDay ? NightLight.sunsetLabel : NightLight.sunriseLabel
        centreX: root._spanX + (1 - root._t0) * root._spanW
        areaWidth: root.width
        visible: root._crosses
    }
}
