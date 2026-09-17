pragma ComponentBehavior: Bound

import QtQuick
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
    property var timeoutStartedAt: createdAt

    signal dismissRequested(int notifId, var notification, bool expired)
    signal leaving()
    signal replyFocusRequested(var owner, bool active)

    // the countdown rings are the frame budget, and a ring that stops ticking for one collapse is invisible
    property bool quietPaint: false

    // one short dashed path per tick, so the stack scales linearly; past a couple of cards nobody reads the arc that closely
    property int stackSize: 1
    readonly property int _ringTickMs: card.stackSize <= 2 ? 33
        : card.stackSize <= 4 ? 50 : 66

    property bool _expired: false
    property bool _leaving: false
    // dismiss-all clears this: every card is leaving, so collapsing heights only drags the lower ones through their own exit
    property bool collapseOnDismiss: true

    function _completeDismiss(): void {
        if (!card._leaving) return
        _exitTimer.stop()
        _collapseAnim.stop()
        card._leaving = false
        card.dismissRequested(card.notifId, card.notification, card._expired)
    }

    readonly property var _defaultAction: {
        const acts = notification.actions ?? []
        for (let i = 0; i < acts.length && i < 64; i++)
            if (acts[i] && Notifications.identityText(acts[i].identifier).toLowerCase() === "default") return acts[i]
        return null
    }
    readonly property var actionList: {
        const acts = notification.actions ?? []
        const out = []
        for (let i = 0; i < acts.length && i < 64 && out.length < 4; i++) {
            const a = acts[i]
            if (!a) continue
            if (Notifications.identityText(a.identifier).toLowerCase() === "default") continue
            if (card._actionText(a).length === 0) continue
            out.push(a)
        }
        return out
    }

    readonly property string appIconSource: {
        Notifications.entriesTick
        return Notifications.appIconSource(
            notification.appIcon, notification.desktopEntry, card.appNameText)
    }
    readonly property string entryIconSource: {
        Notifications.entriesTick
        return Notifications.entryIconSource(notification.desktopEntry, card.appNameText)
    }
    readonly property string notificationImageSource:
        Notifications.notificationImageSource(notification.image)
    readonly property bool hasNotificationImage: notificationImageSource.length > 0

    readonly property string contentImageSource: notificationImageSource
    readonly property bool hasContentImage: contentImageSource.length > 0
    readonly property bool showContentImage: hasContentImage
        && _previewImg.status === Image.Ready
        && _previewImg.implicitWidth >= 200
        && _previewImg.implicitWidth !== _previewImg.implicitHeight
    readonly property bool _previewSettled: !hasContentImage
        || _previewImg.status === Image.Ready || _previewImg.status === Image.Error
    // keep every header on the same text grid. Invalid or absent app icons get an initial instead of collapsing the slot and shifting the whole card
    readonly property bool showIconSlot: _previewSettled

    Accessible.role: Accessible.Notification
    Accessible.name: card.appNameText.length > 0
        ? card.appNameText + ": " + card.summaryText : card.summaryText
    Accessible.description: card.bodyText
    Accessible.focusable: true
    Accessible.onPressAction: card.activatePrimary()

    readonly property string summaryText: Notifications.plainText(notification.summary, 2048)
    readonly property string bodyText:    Notifications.plainText(notification.body)
    readonly property string appNameText: Notifications.identityText(notification.appName)
    readonly property string fallbackInitial: SafeText.initial(
        card.appNameText || card.summaryText, "N")
    readonly property bool hasBody:       bodyText.length > 0
    readonly property bool isCritical: notification.urgency === NotificationUrgency.Critical
    readonly property bool hasInlineReply: notification.hasInlineReply === true
    property bool _replyOpen: false

    readonly property real _cardRadius: Theme.surfaceRadius

    function dismiss(expired): void {
        if (!card.enabled) return
        card.cancelReply()
        card._expired = expired === true
        card._leaving = true
        card.leaving()
        card._collapseBasis = cardRect.height
        _autoClose.stop()
        cardRect.opacity = 0
        cardRect.x = card._hiddenX
        card.enabled = false
        if (!Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
                || !card.visible) {
            card._completeDismiss()
            return
        }
        if (card.collapseOnDismiss) _collapseAnim.restart()
        _exitTimer.start()
    }

    function activatePrimary(): void {
        if (!card.enabled) return
        if (card._defaultAction)
            card._defaultAction.invoke()

        WindowActions.focusNotificationSource(card.notification)
        if (!card._defaultAction || !card.notification.resident)
            card.dismiss()
    }

    function invokeAction(action): void {
        if (!card.enabled || !action) return
        action.invoke()
        if (!card.notification.resident) card.dismiss()
    }

    function _actionText(action): string {
        return Notifications.plainText(action?.text, 256).trim()
    }

    function beginReply(): void {
        if (!card.enabled || !card.hasInlineReply || card._replyOpen) return
        card._replyOpen = true
        card._expanded = true
        card.replyFocusRequested(card, true)
    }

    function focusReplyInput(): void {
        if (!card._replyOpen) return
        _replyInput.forceActiveFocus()
    }

    function cancelReply(): void {
        if (!card._replyOpen) return
        card._replyOpen = false
        _replyInput.text = ""
        card.replyFocusRequested(card, false)
    }

    function _sendInlineReply(text): bool {
        const reply = String(text || "").trim()
        if (!card.enabled || !card.hasInlineReply || reply.length === 0
                || typeof card.notification.sendInlineReply !== "function") return false
        card.notification.sendInlineReply(reply)
        return true
    }

    function submitReply(): void {
        if (!card._sendInlineReply(_replyInput.text)) return
        card._replyOpen = false
        _replyInput.text = ""
        card.replyFocusRequested(card, false)
    }

    onHasInlineReplyChanged: if (!hasInlineReply) card.cancelReply()
    onNotificationChanged: {
        if (card._replyOpen) card.cancelReply()
        else _replyInput.text = ""
    }
    Component.onDestruction: card.replyFocusRequested(card, false)

    NumberAnimation {
        id: _collapseAnim
        target: card; property: "collapseRatio"
        to: 0; duration: Motion.ms(190); easing.type: Easing.InOutCubic
    }

    Timer { id: _exitTimer; interval: Motion.ms(210) + 10; onTriggered: card._completeDismiss() }

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
            _timeLabel = DateTime.clockText(new Date(card._createdAt))
            _timeLive = false
        }
    }

    Component.onCompleted: _updateTime()
    onVisibleChanged: {
        if (!visible && card._leaving) card._completeDismiss()
        else if (visible) card._updateTime()
    }

    Timer {
        id: _timeUpdate
        interval: 30000
        running:  card.visible && ShellSettings.notifPopupEnabled
            && card.enabled && card._timeLive && !Idle.isIdle
        repeat:   true
        onTriggered: card._updateTime()
    }

    implicitWidth:  320
    property real collapseRatio: 1

    property real _collapseBasis: cardRect.height
    implicitHeight: _collapseBasis * collapseRatio
    property int slideDir: 1
    // arrival is flung to cross a full card width in reasonable time; the exit still travels the whole way
    readonly property real _enterX:  slideDir * 44
    readonly property real _hiddenX: slideDir * (implicitWidth + 16)

    // reading one card holds the whole stack: cards expiring out from under the pointer reflow what is being read
    property bool stackHovered: false
    readonly property bool _paused: _cardHover.hovered || card.stackHovered
        || card._replyOpen

    property real _hoverPausedMs: 0
    property real _hoverStartMs:  0

    on_PausedChanged: {
        if (card._paused) {
            card._hoverStartMs = Date.now()
        } else if (card._hoverStartMs > 0) {
            card._hoverPausedMs += Date.now() - card._hoverStartMs
            card._hoverStartMs = 0
        }
    }

    Timer {
        id: _autoClose
        readonly property bool shouldRun: card.isCritical
            ? card.notification.expireTimeout > 0
            : (card.notification.expireTimeout !== 0)
        readonly property real fullInterval: {
            const t = card.notification.expireTimeout
            return (t > 0 && t < 30000) ? t : ShellSettings.notifDefaultTimeout
        }
        interval: Math.max(400, fullInterval - (Date.now() - card.timeoutStartedAt) + card._hoverPausedMs)
        running:  shouldRun && !card._paused
        onTriggered: card.dismiss(true)
    }

    property real _timeoutProgress: 1.0
    property real _countdownPulse:  1.0
    readonly property bool _showCountdown: card.visible && card.enabled
        && _autoClose.shouldRun
        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)

    function _syncCountdown(): void {
        const full = _autoClose.fullInterval
        if (full <= 0) { card._timeoutProgress = 0; return }
        const left = full - (Date.now() - card.timeoutStartedAt) + card._hoverPausedMs
        card._timeoutProgress = Math.max(0, Math.min(1, left / full))
    }

    // measured: a 60fps NumberAnimation here cost ~15% of a core per card, re-running the arc colours, pulse gate and path every vsync
    Timer {
        id: _countdownTick
        interval: card._ringTickMs
        repeat:  true
        running: card._showCountdown && !card._paused && !card.quietPaint
        triggeredOnStart: true
        onTriggered: card._syncCountdown()
    }

    PulseLoop {
        active: card._showCountdown && card._timeoutProgress < 0.18
            && !card._paused && !card.quietPaint
        target: card; targetProperty: "_countdownPulse"
        peak: 0.5; floor: 1.0; restValue: 1.0
        duration: Motion.ms(420)
    }

    HoverHandler { id: _cardHover }

    // Expanding grows the card, and the popup's implicitHeight is quantized, so each step
    // reconfigures the layer surface and can drop the pointer for a frame. Collapsing on
    // that reading shrinks straight back under the cursor and the card oscillates. Plain
    // ms, not a Motion token: those return 0 under reduce motion and re-open the trap.
    property bool _expanded: false
    Timer { id: _collapseHold; interval: 260; onTriggered: if (!card._replyOpen) card._expanded = false }
    Connections {
        target: _cardHover
        function onHoveredChanged() {
            if (_cardHover.hovered) { _collapseHold.stop(); card._expanded = true }
            else _collapseHold.restart()
        }
    }
    // closing the reply from the keyboard leaves no hover edge to collapse the card on
    on_ReplyOpenChanged: if (!card._replyOpen && !_cardHover.hovered) _collapseHold.restart()

    onTimeoutStartedAtChanged: {
        card._hoverPausedMs = 0
        card._hoverStartMs = card._paused ? Date.now() : 0
        card._syncCountdown()
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            // an open reply holds the countdown, so nothing else would ever retire this card
            if (Idle.isIdle) {
                card.cancelReply()
                // this can remove the delegate synchronously: keep it last
                card._completeDismiss()
                return
            }
            card._updateTime()
            card._syncCountdown()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) card._completeDismiss()
        }
    }

    Loader {
        active: card.visible && ShellSettings.barShadow
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
        width:  card.width
        height: Metrics.snap4Up(contentCol.implicitHeight + 26)
        radius: card._cardRadius
        clip:   true
        antialiasing: true

        opacity: 0
        x:       card._enterX

        property bool _behaviorEnabled: false
        // abs: a top-left stack slides to negative x, and a layer toggling off mid-slide flashes the card
        layer.enabled: card.visible
            && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
            && (Math.abs(x) > 0.5 || opacity < 0.999)

        Component.onCompleted: {
            const isNew = !Notifications.isSeen(card.notifId)
            if (isNew) {
                Notifications.markSeen(card.notifId)
                _behaviorEnabled = true
                opacity = 1.0
                x = 0
            } else {
                x = 0
                opacity = 1.0
                Qt.callLater(() => { if (cardRect) cardRect._behaviorEnabled = true })
            }
        }

        MotionBehavior on x       { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: card._leaving ? Motion.ms(200) : Motion.ms(280); easing.type: card._leaving ? Easing.InCubic : Easing.OutCubic } }
        // the fade must outlast the slide both ways: a 140ms fade against the 200ms exit is spent a third of the way out
        MotionBehavior on opacity { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: Motion.ms(200); easing.type: card._leaving ? Easing.InCubic : Easing.OutCubic } }
        MotionBehavior on height  { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }

        // urgency rides the outline, glyph and ring only: tinting the whole fill red drowns the text it is warning about
        // mix() returns alpha 1, so a translucent popup would snap opaque under the cursor
        color: card._expanded
            ? Theme.withAlpha(Theme.mix(Theme.popup, Theme.subtext, 0.06), Theme.popup.a)
            : Theme.popup

        ColorFade on color {}

        ClippingRectangle {
            visible: card.showIconSlot
            width: 24; height: 24
            radius: 6
            color: "transparent"
            anchors.top:        parent.top
            anchors.left:       parent.left
            anchors.topMargin:  13
            anchors.leftMargin: 14

            ShellText {
                anchors.centerIn: parent
                visible: _headerIcon.status !== Image.Ready
                text: card.fallbackInitial
                color: Theme.withAlpha(Theme.subtext, 0.70)
                font.pixelSize: Settings.fontCaption
                font.weight: Font.DemiBold
            }

            IconImage {
                id: _headerIcon
                anchors.fill: parent
                // without this the themed icon decodes at its native size (often 256px+) to paint 24px
                implicitSize: 24
                // a deleted temp icon is still a valid path, so only the load failing reveals it
                property bool _fellBack: false
                readonly property string _primary: card.hasNotificationImage
                    && !card.showContentImage && _previewImg.status === Image.Ready
                    ? card.notificationImageSource : card.appIconSource
                on_PrimaryChanged: _fellBack = false
                source: _fellBack ? card.entryIconSource : _primary
                onStatusChanged: if (status === Image.Error
                        && card.entryIconSource.length > 0
                        && card.entryIconSource !== _primary)
                    _fellBack = true
                asynchronous: true
            }
        }

        Column {
            id: contentCol
            z: 2
            anchors {
                top:         parent.top
                left:        parent.left
                right:       parent.right
                topMargin:   13
                leftMargin:  card.showIconSlot ? 46 : 16
                rightMargin: 16
            }
            spacing: 5

            Item {
                width:  parent.width
                height: _summary.implicitHeight

                ShellText {
                    id: _critIcon
                    visible: card.isCritical
                    anchors.left: parent.left
                    // an expanded summary wraps, so centre on its first line rather than the block
                    anchors.top: _summary.top
                    anchors.topMargin: Math.round((_summary.contentHeight
                        / Math.max(1, _summary.lineCount) - height) / 2)
                    text:           "󰀦"
                    color:          Theme.error
                    font.pixelSize: Settings.fontSize + 1
                }

                ShellText {
                    id: _summary
                    anchors.left:       _critIcon.visible ? _critIcon.right : parent.left
                    anchors.leftMargin: _critIcon.visible ? 6 : 0
                    anchors.right:      parent.right
                    anchors.rightMargin: 30
                    text:             card.summaryText
                    // glyph, rim and ring already carry urgency; red text on the red-tinted fill only costs contrast
                    color:            Theme.text
                    font.pixelSize:   Settings.fontSize + 1
                    font.weight:      Font.DemiBold
                    wrapMode:         Text.Wrap
                    maximumLineCount: card._expanded ? 6 : 1
                    elide:            Text.ElideRight
                    ColorFade on color {}
                }
            }

            ShellText {
                visible:          card.hasBody
                width:            parent.width
                text:             card.bodyText
                color:            Theme.withAlpha(Theme.menuTextMuted, 0.82)
                font.pixelSize:   Settings.fontLabel
                wrapMode:         Text.Wrap
                maximumLineCount: card._expanded ? 12 : 3
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
                        MotionBehavior on width {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            ClippingRectangle {
                id: _previewClip
                visible: card.showContentImage
                width:  parent.width
                height: Math.round(Math.min(150, parent.width * 0.5))
                radius: 8
                color:  "transparent"
                antialiasing: true

                Image {
                    id: _previewImg
                    anchors.fill: parent
                    source: card.hasContentImage ? card.contentImageSource : ""
                    // height bound too: width alone lets a tall portrait decode at full height
                    sourceSize.width: 640
                    sourceSize.height: 640
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // one-shot content, keep it out of the pixmap cache
                    cache: false
                }

                OutlineBorder {
                    radius: _previewClip.radius
                    outlineColor: Theme.menuControlLine
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
                        height: Metrics.rowHeightFor(30)
                        radius: Theme.radiusInline
                        antialiasing: true
                        color: _actMa.pressed       ? Theme.withAlpha(_tint, 0.24)
                             : _actMa.containsMouse ? Theme.withAlpha(_tint, 0.13)
                             :                        Theme.menuControl
                        ColorFade on color {}

                        OutlineBorder {
                            radius: _actBtn.radius
                            outlineColor: (_actMa.containsMouse || _actMa.pressed)
                                ? Theme.withAlpha(_actBtn._tint, 0.50)
                                : Theme.withAlpha(_actBtn._tint, 0.22)
                            ColorFade on outlineColor {}
                        }

                        ShellText {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, _actBtn.width - 16)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: card._actionText(_actBtn.modelData)
                            color: _actMa.containsMouse ? _actBtn._tint : Theme.withAlpha(Theme.text, 0.85)
                            font.pixelSize: Settings.fontLabel
                            font.weight: Font.Medium
                            ColorFade on color {}
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: card._actionText(_actBtn.modelData)
                        Accessible.focusable: true
                        Accessible.onPressAction: card.invokeAction(_actBtn.modelData)

                        MouseArea {
                            id: _actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.invokeAction(_actBtn.modelData)
                        }
                    }
                }
            }

            ActionButton {
                visible: card.hasInlineReply && !card._replyOpen
                width: parent.width
                label: "Reply"
                accessibleName: "Reply to " + (card.appNameText || "notification")
                accentColor: card.isCritical ? Theme.error : Theme.accent
                onTriggered: card.beginReply()
            }

            Rectangle {
                id: _replyField
                visible: card.hasInlineReply && card._replyOpen
                width: parent.width
                height: Metrics.rowHeightFor(36)
                radius: Theme.radiusField
                antialiasing: true
                color: Theme.menuControl

                OutlineBorder {
                    radius: _replyField.radius
                    outlineColor: _replyInput.activeFocus
                        ? Theme.withAlpha(card.isCritical ? Theme.error : Theme.accent,
                            Theme.focusRingSoftAlpha)
                        : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }

                TextInput {
                    id: _replyInput
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.right: _replyCancel.left
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize
                    clip: true
                    maximumLength: 2048
                    onAccepted: card.submitReply()
                    Keys.onEscapePressed: event => {
                        card.cancelReply()
                        event.accepted = true
                    }

                    Accessible.name: "Reply to " + (card.appNameText || "notification")

                    ShellText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: _replyInput.text.length === 0
                        text: Notifications.plainText(
                            card.notification.inlineReplyPlaceholder, 128).trim() || "Reply"
                        color: Theme.withAlpha(Theme.subtext, 0.48)
                        font.pixelSize: Settings.fontSize
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    id: _replyCancel
                    anchors.right: _replySend.left
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: 28
                    glyph: "󰅖"
                    accessibleName: "Cancel reply"
                    onTriggered: card.cancelReply()
                }

                IconButton {
                    id: _replySend
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: 28
                    glyph: "󰒊"
                    accessibleName: "Send reply"
                    enabled: _replyInput.text.trim().length > 0
                    accentColor: card.isCritical ? Theme.error : Theme.accent
                    onTriggered: card.submitReply()
                }
            }

            Row {
                width: parent.width
                spacing: 6

                ShellText {
                    id: _appCap
                    anchors.verticalCenter: parent.verticalCenter
                    visible:        text.length > 0
                    text:           card.appNameText
                    color:          Theme.withAlpha(Theme.menuTextMuted, card.isCritical ? 0.72 : 0.62)
                    font.pixelSize: Settings.fontMicro
                    font.weight:    Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing:  0.6
                    elide:          Text.ElideRight
                    width: Math.min(implicitWidth, Math.max(0, parent.width - _capDot.implicitWidth - _capTime.implicitWidth - parent.spacing * 2))
                }

                ShellText {
                    id: _capDot
                    anchors.verticalCenter: parent.verticalCenter
                    visible: _appCap.visible
                    text:  "·"
                    color: Theme.withAlpha(Theme.menuTextFaint, 0.62)
                    font.pixelSize: Settings.fontMicro
                }

                ShellText {
                    id: _capTime
                    anchors.verticalCenter: parent.verticalCenter
                    text:           card._timeLabel
                    color:          Theme.withAlpha(Theme.menuTextFaint, 0.70)
                    font.pixelSize: Settings.fontMicro
                }
            }
        }

        MouseArea {
            id: _bodyArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) { card.dismiss(); return }
                if (mouse.button === Qt.MiddleButton)
                    WindowActions.focusNotificationSource(card.notification)
                else
                    card.activatePrimary()
            }
        }

        Rectangle {
            anchors.top:         parent.top
            anchors.right:       parent.right
            // the disc rides the content grid and centres on the summary's first line
            anchors.topMargin:   13 + Math.round((_summary.implicitHeight - height) / 2)
            anchors.rightMargin: 16
            width: 24; height: 24; radius: 12
            antialiasing: true
            color:        _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.18) : Theme.menuControl
            opacity: card._expanded ? 1.0 : 0.48

            OutlineBorder {
                radius: 12
                outlineColor: _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.32) : Theme.menuControlLine
                ColorFade on outlineColor {}
            }
            z: 2
            MotionBehavior on opacity      {NumberAnimation { duration: Motion.fast } }
            ColorFade on color {}
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"
            Accessible.focusable: true
            Accessible.onPressAction: card.dismiss()

            HoverHandler { id: _closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler   { onTapped: card.dismiss() }
            ShellText {
                anchors.centerIn: parent
                text:  "󰅖"
                color: _closeHover.hovered ? Theme.error : Theme.withAlpha(Theme.menuTextMuted, 0.78)
                font.pixelSize: Settings.fontCaption
                ColorFade on color {}
            }
        }
    }

    Item {
        id: _cardBorder
        anchors.fill: cardRect
        opacity: cardRect.opacity

        OutlineBorder {
            radius: cardRect.radius
            outlineWidth: card.isCritical ? 2 : 1
            outlineColor: card.isCritical
                ? Theme.withAlpha(Theme.error,  0.62)
                : Theme.outline
            MotionBehavior on outlineColor {
                ColorAnimation { duration: Motion.medium }
            }
        }
    }

    PerimeterProgress {
        anchors.fill: cardRect
        visible: card._showCountdown
        paused:  card.quietPaint
        opacity: cardRect.opacity * card._countdownPulse
        inset:        2.5
        cornerRadius: cardRect.radius
        progress:     card._timeoutProgress
        trackColor:   "transparent"
        arcColor:     card.isCritical ? Theme.error
                    : (card._timeoutProgress < 0.30 ? Theme.warning : Theme.accent)
    }
}
