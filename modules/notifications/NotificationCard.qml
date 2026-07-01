pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../../config"
import "../../services"
import "../common"

Item {
    id: card

    required property var notification
    required property int notifId
    required property var createdAt
    property bool timeoutPaused: false

    signal dismissRequested(int notifId, var notification, bool expired)

    property bool _expired: false

    Accessible.role: Accessible.AlertMessage
    Accessible.name: appNameText
    Accessible.description: hasBody ? summaryText + ": " + bodyText : summaryText

    // "default" action maps to body click per spec, not a chip button
    readonly property var _defaultAction: {
        const acts = notification.actions ?? []
        for (let i = 0; i < acts.length; i++)
            if (acts[i] && String(acts[i].identifier).toLowerCase() === "default") return acts[i]
        return null
    }
    readonly property var actionList: {
        const acts = notification.actions ?? []
        const out = []
        for (let i = 0; i < acts.length && out.length < 4; i++) {
            const a = acts[i]
            if (!a) continue
            if (String(a.identifier).toLowerCase() === "default") continue
            if (!a.text || String(a.text).trim().length === 0) continue
            out.push(a)
        }
        return out
    }

    readonly property string iconSource: {
        const img = notification.image || ""
        if (img.length > 0) return img
        const ai = String(notification.appIcon || "")
        if (ai.length > 0) {
            if (ai.startsWith("/") || ai.startsWith("file://")) return ai
            const p = Quickshell.iconPath(ai, true)
            if (p.length > 0) return p
        }
        const de = DesktopEntries.heuristicLookup(card.appNameText)
        if (de && de.icon) {
            const p2 = Quickshell.iconPath(de.icon, true)
            if (p2.length > 0) return p2
        }
        return ""
    }
    readonly property bool hasIcon: iconSource.length > 0

    readonly property string summaryText: Notifications.plainText(notification.summary)
    readonly property string bodyText:    Notifications.plainText(notification.body)
    readonly property string appNameText: notification.appName || ""
    readonly property bool hasBody:       bodyText.length > 0
    readonly property bool isCritical: notification.urgency === NotificationUrgency.Critical

    readonly property real _cardRadius: Math.min(Theme.radiusPanel, ShellSettings.barHeight / 2)

    function dismiss(expired): void {
        if (!card.enabled) return
        card._expired = expired === true
        card._collapseBasis = cardRect.height
        _autoClose.stop()
        _arrivalShimmer.stop()
        _shimmer.opacity = 0
        cardRect.opacity = 0
        cardRect.x = card._hiddenX
        card.enabled = false
        if (ShellSettings.reduceMotion || !card.visible) {
            card.dismissRequested(card.notifId, card.notification, card._expired)
            return
        }
        _collapseAnim.restart()
        _exitTimer.start()
    }

    NumberAnimation {
        id: _collapseAnim
        target: card; property: "_collapse"
        to: 0; duration: Motion.ms(190); easing.type: Easing.InCubic
    }

    Timer { id: _exitTimer; interval: Motion.ms(210) + 10; onTriggered: card.dismissRequested(card.notifId, card.notification, card._expired) }

    readonly property var   _rawProgress: notification.hints ? notification.hints["value"] : undefined
    readonly property real  _progressNumber: Number(_rawProgress)
    readonly property bool  hasProgress:  _rawProgress !== undefined && _rawProgress !== null && _progressNumber >= 0
    readonly property real  progressValue: hasProgress
        ? Math.max(0, Math.min(1, _progressNumber > 1 ? _progressNumber / 100.0 : _progressNumber))
        : 0

    readonly property real _createdAt: card.createdAt
    property string _timeLabel: "just now"
    property bool   _timeLive:  true

    function _updateTime(): void {
        const secs = (Date.now() - card._createdAt) / 1000
        if (secs < 60)        _timeLabel = "just now"
        else if (secs < 3600) _timeLabel = Math.floor(secs / 60) + "m ago"
        else {
            const d = new Date(card._createdAt)
            _timeLabel = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
            _timeLive = false
        }
    }

    Component.onCompleted: _updateTime()
    onVisibleChanged: if (visible) _updateTime()

    Timer {
        id: _timeUpdate
        interval: 30000
        running:  card.visible && ShellSettings.notifPopupEnabled
            && card.enabled && card._timeLive
        repeat:   true
        onTriggered: card._updateTime()
    }

    implicitWidth:  320
    // collapses during dismiss so cards below glide up
    property real _collapse: 1

    property real _collapseBasis: cardRect.height
    implicitHeight: _collapseBasis * _collapse
    property int slideDir: 1
    readonly property real _hiddenX: slideDir * (implicitWidth + 16)

    // accumulated hover time, added back so timeout doesn't count time spent hovering
    property real _hoverPausedMs: 0
    property real _hoverStartMs:  0
    property real _hiddenStartMs: 0

    onTimeoutPausedChanged: {
        if (timeoutPaused) {
            if (_hiddenStartMs <= 0) _hiddenStartMs = Date.now()
        } else if (_hiddenStartMs > 0) {
            _hoverPausedMs += Date.now() - _hiddenStartMs
            _hiddenStartMs = 0
        }
    }

    Timer {
        id: _autoClose
        // critical stays resident unless sender sets explicit timeout
        readonly property bool shouldRun: card.isCritical
            ? card.notification.expireTimeout > 0
            : (card.notification.expireTimeout !== 0)
        readonly property real fullInterval: {
            const t = card.notification.expireTimeout
            return (t > 0 && t < 30000) ? t : ShellSettings.notifDefaultTimeout
        }
        // anchor to arrival time from model, not delegate creation, survives list rebuilds
        interval: Math.max(400, fullInterval - (Date.now() - card._createdAt) + card._hoverPausedMs)
        running:  shouldRun && !_cardHover.hovered && !card.timeoutPaused
        onTriggered: card.dismiss(true)
    }

    property real _timeoutProgress: 1.0
    property real _countdownPulse:  1.0
    readonly property bool _showCountdown: card.visible && card.enabled
        && _autoClose.shouldRun && !card.timeoutPaused && !ShellSettings.reduceMotion
    readonly property real _trueRemaining: Math.max(0, _autoClose.fullInterval - (Date.now() - card._createdAt) + card._hoverPausedMs)

    NumberAnimation {
        id: _countdownAnim
        target: card; property: "_timeoutProgress"
        from: _autoClose.fullInterval > 0 ? Math.min(1, card._trueRemaining / _autoClose.fullInterval) : 0
        to:   0
        duration: Math.max(1, card._trueRemaining)
        running:  card._showCountdown
    }

    // bound only while running — assigning paused on a stopped animation warns
    Binding {
        target: _countdownAnim
        property: "paused"
        value: _cardHover.hovered || card.timeoutPaused
        when: _countdownAnim.running
        restoreMode: Binding.RestoreNone
    }

    SequentialAnimation {
        running: card._showCountdown && card._timeoutProgress < 0.18 && !_cardHover.hovered && !card.timeoutPaused
        loops:   Animation.Infinite
        onRunningChanged: if (!running) card._countdownPulse = 1.0
        NumberAnimation { target: card; property: "_countdownPulse"; to: 0.5; duration: Motion.ms(420); easing.type: Easing.InOutSine }
        NumberAnimation { target: card; property: "_countdownPulse"; to: 1.0; duration: Motion.ms(420); easing.type: Easing.InOutSine }
    }

    HoverHandler {
        id: _cardHover
        onHoveredChanged: {
            if (hovered) {
                card._hoverStartMs = Date.now()
            } else if (card._hoverStartMs > 0) {
                card._hoverPausedMs += Date.now() - card._hoverStartMs
                card._hoverStartMs = 0
            }
        }
    }


    Loader {
        active: card.visible && ShellSettings.barFloating && ShellSettings.barShadow
        anchors.fill: cardRect
        opacity: cardRect.opacity
        z: -1
        sourceComponent: FloatingShadow {
            radius: card._cardRadius
            atBottom: ShellSettings.barPosition === "bottom"
        }
    }

    Rectangle {
        id: cardRect
        width:  parent.implicitWidth
        height: Math.round(contentCol.implicitHeight) + 26
        radius: card._cardRadius
        clip:   true
        antialiasing: true

        opacity: 0
        x:       card._hiddenX

        property bool _behaviorEnabled: false
        layer.enabled: card.visible && !ShellSettings.reduceMotion
            && (_arrivalShimmer.running || x > 0.5 || opacity < 0.999)

        Component.onCompleted: {
            const isNew = !Notifications.isSeen(card.notifId)
            if (isNew) {
                Notifications.markSeen(card.notifId)
                _behaviorEnabled = true
                opacity = 1.0
                x = 0
                if (card.visible && !ShellSettings.reduceMotion) _arrivalShimmer.restart()
            } else {
                x = 0
                opacity = 1.0
                Qt.callLater(() => { cardRect._behaviorEnabled = true })
            }
        }

        Behavior on x       { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(200); easing.type: Easing.OutQuart } }
        Behavior on opacity { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(140) } }
        Behavior on height  { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }

        // Fill only, the border lives in a separate overlay (_cardBorder) so the
        // layer/clip used for the shimmer can't clip the antialiased border edges.
        // Popup base: same opaque chrome tone as the menu/calendar (and the bar's
        // hue) so a standalone card reads as one family, not a lighter floating row.
        color: Theme.rowFill(_cardHover.hovered, card.isCritical)

        Behavior on color { ColorAnimation { duration: Motion.fast } }

        ClippingRectangle {
            visible: card.hasIcon
            width: 24; height: 24
            radius: 6
            color: "transparent"
            anchors.top:        parent.top
            anchors.left:       parent.left
            anchors.topMargin:  13
            anchors.leftMargin: 14
            Image {
                anchors.fill: parent
                source: card.iconSource
                sourceSize.width:  48
                sourceSize.height: 48
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Column {
            id: contentCol
            z: 2   // above _bodyArea so the action chips get their clicks
            anchors {
                top:         parent.top
                left:        parent.left
                right:       parent.right
                topMargin:   13
                leftMargin:  card.hasIcon ? 46 : 16
                rightMargin: 16
            }
            spacing: 5

            Item {
                width:  parent.width
                height: _summary.implicitHeight

                Text {
                    id: _critIcon
                    visible: card.isCritical
                    anchors.left: parent.left
                    anchors.verticalCenter: _summary.verticalCenter
                    text:           "󰀦"
                    color:          Theme.error
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize + 1
                    renderType:     Text.NativeRendering
                }

                Text {
                    id: _summary
                    anchors.left:       _critIcon.visible ? _critIcon.right : parent.left
                    anchors.leftMargin: _critIcon.visible ? 6 : 0
                    anchors.right:      parent.right
                    text:           card.summaryText
                    textFormat:     Text.PlainText
                    color:          card.isCritical ? Theme.error : Theme.text
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize + 1
                    font.weight:    Font.DemiBold
                    renderType:     Text.NativeRendering
                    elide:          Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }

            Text {
                visible:          card.hasBody
                width:            parent.width
                text:             card.bodyText
                textFormat:       Text.PlainText
                color:            Theme.withAlpha(Theme.menuTextMuted, 0.82)
                font.family:      Settings.font
                font.pixelSize:   Settings.fontSize - 1
                renderType:       Text.NativeRendering
                wrapMode:         Text.WordWrap
                // hover reveals the full body instead of leaving it truncated
                maximumLineCount: _cardHover.hovered ? 12 : 3
                elide:            Text.ElideRight
            }

            Item {
                visible: card.hasProgress
                width:   parent.width
                height:  visible ? 10 : 0

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width:  parent.width
                    height: 3; radius: 1.5
                    color:  Theme.menuTrack

                    Rectangle {
                        width: {
                            const v = Math.max(0, Math.min(1, card.progressValue))
                            return v <= 0 ? 0 : Math.max(parent.radius * 2, parent.width * v)
                        }
                        height: parent.height; radius: parent.radius
                        color:  Theme.accent
                        Behavior on width {
                            enabled: !ShellSettings.reduceMotion
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Row {
                visible: card.actionList.length > 0
                width: parent.width
                topPadding: 4
                bottomPadding: 2
                spacing: 7

                Repeater {
                    model: card.actionList
                    delegate: Rectangle {
                        id: _actBtn
                        required property var modelData
                        readonly property color _tint: card.isCritical ? Theme.error : Theme.accent
                        readonly property int _n: Math.max(1, card.actionList.length)

                        width: (contentCol.width - 7 * (_n - 1)) / _n
                        height: 28
                        radius: 8
                        antialiasing: true
                        color: _actMa.pressed       ? Theme.withAlpha(_tint, 0.24)
                             : _actMa.containsMouse ? Theme.withAlpha(_tint, 0.13)
                             :                        Theme.menuControl
                        border.width: 1
                        border.color: (_actMa.containsMouse || _actMa.pressed)
                            ? Theme.withAlpha(_tint, 0.50)
                            : Theme.withAlpha(_tint, 0.22)
                        Behavior on color        { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: _actBtn.modelData.text

                        Text {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, _actBtn.width - 16)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: _actBtn.modelData.text
                            textFormat: Text.PlainText
                            color: _actMa.containsMouse ? _actBtn._tint : Theme.withAlpha(Theme.text, 0.85)
                            font.family: Settings.font
                            font.pixelSize: Settings.fontSize - 1
                            font.weight: Font.Medium
                            renderType: Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        MouseArea {
                            id: _actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!card.enabled) return
                                _actBtn.modelData.invoke()
                                card.dismiss()
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 6

                Text {
                    id: _appCap
                    anchors.verticalCenter: parent.verticalCenter
                    visible:        text.length > 0
                    text:           card.appNameText
                    textFormat:     Text.PlainText
                    color:          Theme.withAlpha(Theme.menuTextMuted, card.isCritical ? 0.92 : 0.62)
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize - 3
                    font.weight:    Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing:  0.6
                    renderType:     Text.NativeRendering
                    elide:          Text.ElideRight
                    width: Math.min(implicitWidth, Math.max(0, parent.width - _capDot.implicitWidth - _capTime.implicitWidth - parent.spacing * 2))
                }

                Text {
                    id: _capDot
                    anchors.verticalCenter: parent.verticalCenter
                    visible: _appCap.visible
                    text:  "·"
                    color: Theme.withAlpha(Theme.menuTextFaint, 0.62)
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize - 3
                    renderType:     Text.NativeRendering
                }

                Text {
                    id: _capTime
                    anchors.verticalCenter: parent.verticalCenter
                    text:           card._timeLabel
                    textFormat:     Text.PlainText
                    color:          Theme.withAlpha(Theme.menuTextFaint, 0.70)
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize - 3
                    renderType:     Text.NativeRendering
                }
            }
        }

        Rectangle {
            id: _shimmer
            x: -width; y: -parent.height * 0.35
            width: 76; height: parent.height * 1.7
            rotation: 12; opacity: 0
            transformOrigin: Item.Center
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Theme.withAlpha(Theme.text, 0.00) }
                GradientStop { position: 0.48; color: Theme.withAlpha(Theme.text, card.isCritical ? 0.18 : 0.10) }
                GradientStop { position: 1.00; color: Theme.withAlpha(Theme.text, 0.00) }
            }
        }

        SequentialAnimation {
            id: _arrivalShimmer
            PauseAnimation { duration: Motion.ms(120) }
            ParallelAnimation {
                NumberAnimation { target: _shimmer; property: "x"; from: -_shimmer.width; to: cardRect.width + _shimmer.width; duration: Motion.ms(620); easing.type: Easing.Linear }
                SequentialAnimation {
                    NumberAnimation { target: _shimmer; property: "opacity"; from: 0; to: 1;   duration: Motion.ms(160); easing.type: Easing.OutCubic }
                    PauseAnimation  { duration: Motion.ms(260) }
                    NumberAnimation { target: _shimmer; property: "opacity"; to: 0;            duration: Motion.ms(300); easing.type: Easing.InCubic }
                }
            }
            ScriptAction { script: { _shimmer.opacity = 0; _shimmer.x = -_shimmer.width } }
        }

        MouseArea {
            id: _bodyArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) { card.dismiss(); return }
                // default action first (app-side open/reply), then raise the window
                if (mouse.button !== Qt.MiddleButton && card._defaultAction)
                    card._defaultAction.invoke()
                HyprActions.focusNotificationSource(card.notification)
                if (mouse.button !== Qt.MiddleButton)
                    card.dismiss()
            }
        }

        Rectangle {
            anchors.top:         parent.top
            anchors.right:       parent.right
            anchors.topMargin:   7
            anchors.rightMargin: 7
            width: 18; height: 18; radius: 9
            antialiasing: true
            color:        _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.18) : Theme.menuControl
            border.width: 1
            border.color: _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.32) : Theme.menuControlLine
            opacity: _cardHover.hovered ? 1.0 : 0.0
            scale:   _cardHover.hovered ? 1.0 : 0.6
            transformOrigin: Item.Center
            z: 2
            Behavior on opacity      { NumberAnimation { duration: Motion.fast } }
            Behavior on scale        { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on color        { ColorAnimation  { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation  { duration: Motion.fast } }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"
            HoverHandler { id: _closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler   { onTapped: card.dismiss() }
            Text {
                anchors.centerIn: parent
                text:  "󰅖"
                color: _closeHover.hovered ? Theme.error : Theme.withAlpha(Theme.menuTextMuted, 0.78)
                font.family:    Settings.font
                font.pixelSize: Settings.fontSize - 2
                renderType:     Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    // border outside clip/layer so shimmer doesn't cut antialiased edges
    Rectangle {
        id: _cardBorder
        anchors.fill: cardRect
        radius:  cardRect.radius
        color:   "transparent"
        antialiasing: true
        opacity: cardRect.opacity
        visible: !card._showCountdown
        border.width: 1
        border.color: card.isCritical
            ? Theme.withAlpha(Theme.error,  0.55)
            : Theme.menuCardBorder
        Behavior on border.color { ColorAnimation { duration: Motion.medium } }
    }

    Canvas {
        id: _countdownArc
        anchors.fill: cardRect
        visible: card._showCountdown
        opacity: cardRect.opacity * card._countdownPulse
        antialiasing: true
        renderTarget:   Canvas.Image
        renderStrategy: Canvas.Threaded

        readonly property color arcColor: card.isCritical ? Theme.error
                                        : (card._timeoutProgress < 0.30 ? Theme.warning : Theme.accent)
        readonly property color trackColor: Theme.menuControlLine
        property real progress: card._timeoutProgress

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            const inset = 2.5
            const r = Math.max(0.5, cardRect.radius - inset)
            const x = inset, y = inset
            const w = width - inset * 2, h = height - inset * 2
            const sx = Math.max(0, w - 2 * r), sy = Math.max(0, h - 2 * r)
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
            ctx.strokeStyle = _countdownArc.trackColor
            ctx.stroke()

            const p = _countdownArc.progress
            if (p <= 0.002) return
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
            ctx.strokeStyle = _countdownArc.arcColor
            ctx.stroke()
        }

        onVisibleChanged:  { _painted = progress; _lastPaintMs = 0; requestPaint() }
        onWidthChanged:    if (visible) requestPaint()
        onHeightChanged:   if (visible) requestPaint()
        onArcColorChanged: if (visible) requestPaint()
        onTrackColorChanged: if (visible) requestPaint()
        // repaint per ~1px of perimeter travel, skip sub-pixel moves
        property real _painted: -1
        // cap to ~33fps — the arc ticks every vsync frame otherwise, each a threaded-canvas upload
        property real _lastPaintMs: 0
        onProgressChanged: {
            if (!visible) return
            const now = Date.now()
            if (now - _lastPaintMs < 30) return
            if (Math.abs(progress - _painted) * 2 * (width + height) < 1.0) return
            _painted = progress
            _lastPaintMs = now
            requestPaint()
        }
    }
}
