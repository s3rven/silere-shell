import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property real progress: 0
    property color accentColor: Theme.accent
    property bool showGauge: true
    property real alertPulse: 0
    property string hoverValue: ""
    // The Now page keeps feeding SysInfo polls while the menu sits on another
    // tab. When this tile isn't being shown, snap the arc instead of running a
    // 500ms fill animation (+ canvas repaints) nobody can see.
    property bool active: true

    readonly property bool _hoverable: hoverValue.length > 0

    height: showGauge ? 56 : 44   // 4px multiples

    // hoverValue is mouse-only by design; surface it here too so a screen
    // reader gets it regardless of pointer state.
    Accessible.role: Accessible.StaticText
    Accessible.name: root.label
    Accessible.description: root._hoverable ? root.value + "  " + root.hoverValue : root.value

    HoverHandler { id: _hover; enabled: root._hoverable }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusCard
        antialiasing: true
        color: Theme.menuControl
    }

    // Glyph slot — same position as QuickToggleTile.
    Item {
        id: _glyphSlot
        anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
        width: 22; height: 22

        Text {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: Theme.mix(root.accentColor, Theme.error, root.alertPulse * 0.6)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 5
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.medium } }
        }
    }

    // Label (identifier) + value (reading) — mirrors QuickToggleTile title/status.
    Column {
        anchors {
            left: _glyphSlot.right; leftMargin: 11
            right: parent.right;    rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
            width: parent.width
            text: root.label
            color: Theme.withAlpha(Theme.text, 0.88)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Text {
            id: _valText
            width: parent.width
            text: root._valShown
            color: root._valAlt
                ? Theme.withAlpha(root.accentColor, 0.60)
                : Theme.withAlpha(root.accentColor, 0.85)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize - 2
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.medium } }
        }
    }

    property string _valShown: root.value
    readonly property bool _valAlt: _hover.hovered && root._hoverable
    on_ValAltChanged: {
        if (!root._hoverable) return
        if (ShellSettings.reduceMotion) { root._valShown = root._valAlt ? root.hoverValue : root.value; return }
        _valSwap.restart()
    }

    SequentialAnimation {
        id: _valSwap
        NumberAnimation { target: _valText; property: "opacity"; to: 0; duration: Motion.instant; easing.type: Easing.InCubic }
        ScriptAction    { script: root._valShown = root._valAlt ? root.hoverValue : root.value }
        NumberAnimation { target: _valText; property: "opacity"; to: 1; duration: Motion.fast; easing.type: Easing.OutCubic }
    }

    Connections {
        target: root
        function onValueChanged() { if (!root._valAlt && !_valSwap.running) root._valShown = root.value }
    }

    // Border arc — same Canvas technique as NotificationCard's countdown arc.
    // alertPulse is intentionally absent from _arcColor: including it would make
    // the color binding re-evaluate at 60fps and trigger canvas repaints for every
    // pulse tick. The pulse glow lives instead in a cheap Rectangle overlay below.
    Canvas {
        id: _arc
        anchors.fill: parent
        antialiasing: true
        renderTarget:   Canvas.Image
        renderStrategy: Canvas.Threaded

        property real  _prog:       root._disp
        // Only changes on accentColor threshold-crossings (hot/critical), not per-frame.
        property color _arcColor:   root.accentColor
        property color _trackColor: Theme.withAlpha(root.accentColor, 0.13)

        property real _painted: -1

        // Repaint per ~1px of arc travel, not a fixed fraction, so the fill reads
        // smooth instead of stepping; sub-pixel changes are skipped.
        on_ProgChanged:       { if (Math.abs(_prog - _painted) * 2 * (width + height) < 1.0) return; _painted = _prog; requestPaint() }
        on_ArcColorChanged:   requestPaint()
        on_TrackColorChanged: requestPaint()
        onVisibleChanged:     { _painted = -1; requestPaint() }
        onWidthChanged:       requestPaint()
        onHeightChanged:      requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return

            const inset = 1.5
            const r  = Math.max(0.5, Theme.radiusCard - inset)
            const x  = inset,     y  = inset
            const w  = width  - inset * 2
            const h  = height - inset * 2
            const sx = Math.max(0, w - 2 * r)
            const sy = Math.max(0, h - 2 * r)
            const ar = Math.PI / 2 * r

            function outline() {
                ctx.beginPath()
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + w - r, y)
                ctx.arc(x + w - r, y + r,     r, -Math.PI / 2, 0)
                ctx.lineTo(x + w, y + h - r)
                ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2)
                ctx.lineTo(x + r, y + h)
                ctx.arc(x + r, y + h - r,     r, Math.PI / 2, Math.PI)
                ctx.lineTo(x, y + r)
                ctx.arc(x + r, y + r,         r, Math.PI, 3 * Math.PI / 2)
            }

            outline()
            ctx.lineWidth   = 1
            ctx.strokeStyle = _arc._trackColor
            ctx.stroke()

            const p = _arc._prog
            if (p <= 0.002 || !root.showGauge) return
            let t = p * (2 * sx + 2 * sy + 4 * ar)
            let l
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            l = Math.min(t, sx); ctx.lineTo(x + r + l, y); t -= l
            if (t > 0) { l = Math.min(t, ar); ctx.arc(x + w - r, y + r,     r, -Math.PI / 2, -Math.PI / 2 + l / r); t -= l }
            if (t > 0) { l = Math.min(t, sy); ctx.lineTo(x + w, y + r + l); t -= l }
            if (t > 0) { l = Math.min(t, ar); ctx.arc(x + w - r, y + h - r, r, 0, l / r); t -= l }
            if (t > 0) { l = Math.min(t, sx); ctx.lineTo(x + w - r - l, y + h); t -= l }
            if (t > 0) { l = Math.min(t, ar); ctx.arc(x + r, y + h - r,     r, Math.PI / 2, Math.PI / 2 + l / r); t -= l }
            if (t > 0) { l = Math.min(t, sy); ctx.lineTo(x, y + h - r - l); t -= l }
            if (t > 0) { l = Math.min(t, ar); ctx.arc(x + r, y + r,         r, Math.PI, Math.PI + l / r); t -= l }
            ctx.lineWidth   = 1.5
            ctx.lineCap     = "round"
            ctx.strokeStyle = _arc._arcColor
            ctx.stroke()
        }
    }

    // Alert-pulse glow overlay. Rectangle color binding is GPU-composited, so
    // alertPulse driving this at 60fps costs nothing vs. a canvas repaint.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusCard
        antialiasing: true
        visible: root.alertPulse > 0.001
        color: "transparent"
        border.width: 1
        border.color: Theme.withAlpha(root.accentColor, root.alertPulse * 0.35)
    }

    property real _disp: 0

    NumberAnimation {
        id: _fillAnim
        target: root; property: "_disp"
        duration: Motion.ms(500)
        easing.type: Easing.OutCubic
    }

    function animateIn(delay: int): void {
        _fillAnim.stop()
        _disp = 0
        _fillDelay.interval = delay
        _fillDelay.restart()
    }

    Timer {
        id: _fillDelay
        onTriggered: {
            if (ShellSettings.reduceMotion) { root._disp = root.progress; return }
            _fillAnim.from = root._disp
            _fillAnim.to   = root.progress
            _fillAnim.restart()
        }
    }

    onProgressChanged: {
        if (_fillDelay.running) return
        if (!root.active || ShellSettings.reduceMotion) { _disp = progress; return }
        _fillAnim.from = _disp
        _fillAnim.to   = progress
        _fillAnim.restart()
    }
}
