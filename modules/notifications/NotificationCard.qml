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

    Accessible.role: Accessible.AlertMessage
    Accessible.name: appNameText
    Accessible.description: hasBody ? summaryText + ": " + bodyText : summaryText
    Accessible.onPressAction: card.activatePrimary()

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

    readonly property string appIconSource: Notifications.appIconSource(
        notification.appIcon, notification.desktopEntry, card.appNameText)
    readonly property string notificationImageSource: Notifications.fileUrl(notification.image)
    readonly property bool hasAppIcon: appIconSource.length > 0
    readonly property bool hasNotificationImage: notificationImageSource.length > 0

    readonly property string contentImageSource: notificationImageSource
    readonly property bool hasContentImage: contentImageSource.length > 0
    readonly property string contentImageTarget: contentImageSource.startsWith("/")
        || contentImageSource.startsWith("file:") ? contentImageSource : ""
    readonly property bool showContentImage: hasContentImage
        && _previewImg.status === Image.Ready
        && _previewImg.implicitWidth >= 200
        && _previewImg.implicitWidth !== _previewImg.implicitHeight
    readonly property bool _previewSettled: !hasContentImage
        || _previewImg.status === Image.Ready || _previewImg.status === Image.Error
    readonly property bool showIconSlot: _previewSettled && (hasAppIcon
        || (hasNotificationImage && _previewImg.status === Image.Ready && !showContentImage))

    readonly property string summaryText: Notifications.plainText(notification.summary, 2048)
    readonly property string bodyText:    Notifications.plainText(notification.body)
    readonly property string appNameText: Notifications.identityText(notification.appName)
    readonly property bool hasBody:       bodyText.length > 0
    readonly property bool isCritical: notification.urgency === NotificationUrgency.Critical

    readonly property real _cardRadius: Theme.surfaceRadius

    function dismiss(expired): void {
        if (!card.enabled) return
        card._expired = expired === true
        card._leaving = true
        card.leaving()
        card._collapseBasis = cardRect.height
        _autoClose.stop()
        cardRect.opacity = 0
        cardRect.x = card._hiddenX
        card.enabled = false
        if (ShellSettings.reduceMotion || !card.visible) {
            card.dismissRequested(card.notifId, card.notification, card._expired)
            return
        }
        if (card.collapseOnDismiss) _collapseAnim.restart()
        _exitTimer.start()
    }

    function activatePrimary(): void {
        if (!card.enabled) return
        if (card._defaultAction)
            card._defaultAction.invoke()
        else if (card.showContentImage && card.contentImageTarget.length > 0)
            Qt.openUrlExternally(card.contentImageTarget)

        HyprActions.focusNotificationSource(card.notification)
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

    NumberAnimation {
        id: _collapseAnim
        target: card; property: "collapseRatio"
        to: 0; duration: Motion.ms(190); easing.type: Easing.InOutCubic
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
    property real collapseRatio: 1

    property real _collapseBasis: cardRect.height
    implicitHeight: _collapseBasis * collapseRatio
    property int slideDir: 1
    // arrival is flung to cross a full card width in reasonable time; the exit still travels the whole way
    readonly property real _enterX:  slideDir * 44
    readonly property real _hiddenX: slideDir * (implicitWidth + 16)

    property real _hoverPausedMs: 0
    property real _hoverStartMs:  0

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
        running:  shouldRun && !_cardHover.hovered
        onTriggered: card.dismiss(true)
    }

    property real _timeoutProgress: 1.0
    property real _countdownPulse:  1.0
    readonly property bool _showCountdown: card.visible && card.enabled
        && _autoClose.shouldRun && !ShellSettings.reduceMotion

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
        running: card._showCountdown && !_cardHover.hovered && !card.quietPaint
        triggeredOnStart: true
        onTriggered: card._syncCountdown()
    }

    PulseLoop {
        active: card._showCountdown && card._timeoutProgress < 0.18
            && !_cardHover.hovered && !card.quietPaint
        target: card; targetProperty: "_countdownPulse"
        peak: 0.5; floor: 1.0; restValue: 1.0
        duration: Motion.ms(420)
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

    onTimeoutStartedAtChanged: {
        card._hoverPausedMs = 0
        card._hoverStartMs = _cardHover.hovered ? Date.now() : 0
        card._syncCountdown()
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
        width:  card.width
        height: Math.round(contentCol.implicitHeight) + 26
        radius: card._cardRadius
        clip:   true
        antialiasing: true

        opacity: 0
        x:       card._enterX

        property bool _behaviorEnabled: false
        // abs: a top-left stack slides to negative x, and a layer toggling off mid-slide flashes the card
        layer.enabled: card.visible && !ShellSettings.reduceMotion
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
                Qt.callLater(() => { cardRect._behaviorEnabled = true })
            }
        }

        MotionBehavior on x       { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: card._leaving ? Motion.ms(200) : Motion.ms(280); easing.type: card._leaving ? Easing.InCubic : Easing.OutCubic } }
        // the fade must outlast the slide both ways: a 140ms fade against the 200ms exit is spent a third of the way out
        MotionBehavior on opacity { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: Motion.ms(200); easing.type: card._leaving ? Easing.InCubic : Easing.OutCubic } }
        MotionBehavior on height  { gate: card.visible && cardRect._behaviorEnabled; NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }

        // same opaque chrome tone as the menu/calendar/tray popups, or a standalone card reads as a lighter floating row
        color: card.isCritical
            ? Theme.mix(Theme.popup, Theme.error, _cardHover.hovered ? 0.17 : 0.12)
            : (_cardHover.hovered ? Theme.mix(Theme.popup, Theme.subtext, 0.06) : Theme.popup)

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
            IconImage {
                anchors.fill: parent
                source: card.hasNotificationImage && !card.showContentImage
                    && _previewImg.status === Image.Ready
                    ? card.notificationImageSource : card.appIconSource
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
                    anchors.verticalCenter: _summary.verticalCenter
                    text:           "󰀦"
                    color:          Theme.error
                    font.pixelSize: Settings.fontSize + 1
                }

                ShellText {
                    id: _summary
                    anchors.left:       _critIcon.visible ? _critIcon.right : parent.left
                    anchors.leftMargin: _critIcon.visible ? 6 : 0
                    anchors.right:      parent.right
                    anchors.rightMargin: 18
                    text:           card.summaryText
                    // glyph, rim and ring already carry urgency; red text on the red-tinted fill only costs contrast
                    color:          Theme.text
                    font.pixelSize: Settings.fontSize + 1
                    font.weight:    Font.DemiBold
                    elide:          Text.ElideRight
                    ColorFade on color {}
                }
            }

            ShellText {
                visible:          card.hasBody
                width:            parent.width
                text:             card.bodyText
                color:            Theme.withAlpha(Theme.menuTextMuted, 0.82)
                font.pixelSize:   Settings.fontSize - 1
                wrapMode:         Text.WordWrap
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
                        height: 30
                        radius: 8
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

                        Accessible.role: Accessible.Button
                        Accessible.name: card._actionText(_actBtn.modelData)
                        Accessible.onPressAction: card.invokeAction(_actBtn.modelData)

                        ShellText {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, _actBtn.width - 16)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: card._actionText(_actBtn.modelData)
                            color: _actMa.containsMouse ? _actBtn._tint : Theme.withAlpha(Theme.text, 0.85)
                            font.pixelSize: Settings.fontSize - 1
                            font.weight: Font.Medium
                            ColorFade on color {}
                        }

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

            Row {
                width: parent.width
                spacing: 6

                ShellText {
                    id: _appCap
                    anchors.verticalCenter: parent.verticalCenter
                    visible:        text.length > 0
                    text:           card.appNameText
                    color:          Theme.withAlpha(Theme.menuTextMuted, card.isCritical ? 0.72 : 0.62)
                    font.pixelSize: Settings.fontSize - 3
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
                    font.pixelSize: Settings.fontSize - 3
                }

                ShellText {
                    id: _capTime
                    anchors.verticalCenter: parent.verticalCenter
                    text:           card._timeLabel
                    color:          Theme.withAlpha(Theme.menuTextFaint, 0.70)
                    font.pixelSize: Settings.fontSize - 3
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
                    HyprActions.focusNotificationSource(card.notification)
                else
                    card.activatePrimary()
            }
        }

        Rectangle {
            anchors.top:         parent.top
            anchors.right:       parent.right
            anchors.topMargin:   7
            anchors.rightMargin: 7
            width: 22; height: 22; radius: 11
            antialiasing: true
            color:        _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.18) : Theme.menuControl
            opacity: _cardHover.hovered ? 1.0 : 0.48

            OutlineBorder {
                radius: 11
                outlineColor: _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.32) : Theme.menuControlLine
                ColorFade on outlineColor {}
            }
            scale:   _cardHover.hovered ? 1.0 : 0.90
            transformOrigin: Item.Center
            z: 2
            MotionBehavior on opacity      {NumberAnimation { duration: Motion.fast } }
            MotionBehavior on scale        {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            ColorFade on color {}
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"
            Accessible.onPressAction: card.dismiss()
            HoverHandler { id: _closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler   { onTapped: card.dismiss() }
            ShellText {
                anchors.centerIn: parent
                text:  "󰅖"
                color: _closeHover.hovered ? Theme.error : Theme.withAlpha(Theme.menuTextMuted, 0.78)
                font.pixelSize: Settings.fontSize - 2
                ColorFade on color {}
            }
        }
    }

    Item {
        id: _cardBorder
        anchors.fill: cardRect
        opacity: cardRect.opacity
        visible: !card._showCountdown

        OutlineBorder {
            radius: cardRect.radius
            outlineColor: card.isCritical
                ? Theme.withAlpha(Theme.error,  0.32)
                : Theme.outline
            MotionBehavior on outlineColor {ColorAnimation { duration: Motion.medium } }
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
        trackColor:   Theme.menuControlLine
        arcColor:     card.isCritical ? Theme.error
                    : (card._timeoutProgress < 0.30 ? Theme.warning : Theme.accent)
    }
}
