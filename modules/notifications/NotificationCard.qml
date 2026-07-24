pragma ComponentBehavior: Bound

import QtQuick
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
    property var timeoutStartedAt: createdAt

    signal dismissRequested(int notifId, var notification, bool expired)

    property bool _expired: false
    property bool _leaving: false

    Accessible.role: Accessible.AlertMessage
    Accessible.name: appNameText
    Accessible.description: hasBody ? summaryText + ": " + bodyText : summaryText
    Accessible.onPressAction: card.activatePrimary()

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

    readonly property string summaryText: Notifications.plainText(notification.summary)
    readonly property string bodyText:    Notifications.plainText(notification.body)
    readonly property string appNameText: notification.appName || ""
    readonly property bool hasBody:       bodyText.length > 0
    readonly property bool isCritical: notification.urgency === NotificationUrgency.Critical

    readonly property real _cardRadius: Math.min(Theme.radiusPanel, ShellSettings.barHeight / 2)

    function dismiss(expired): void {
        if (!card.enabled) return
        card._expired = expired === true
        card._leaving = true
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

    function activatePrimary(): void {
        if (!card.enabled) return
        if (card._defaultAction)
            card._defaultAction.invoke()
        else if (card.showContentImage && card.contentImageTarget.length > 0)
            Quickshell.execDetached(["xdg-open", card.contentImageTarget])

        HyprActions.focusNotificationSource(card.notification)
        if (!card._defaultAction || !card.notification.resident)
            card.dismiss()
    }

    function invokeAction(action): void {
        if (!card.enabled || !action) return
        action.invoke()
        // `resident` asks the server to keep the notification after an
        // action is invoked.
        if (!card.notification.resident) card.dismiss()
    }

    NumberAnimation {
        id: _collapseAnim
        target: card; property: "collapseRatio"
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
    property real collapseRatio: 1

    property real _collapseBasis: cardRect.height
    implicitHeight: _collapseBasis * collapseRatio
    property int slideDir: 1
    readonly property real _hiddenX: slideDir * (implicitWidth + 16)

    // accumulated hover time, added back so timeout doesn't count time spent hovering
    property real _hoverPausedMs: 0
    property real _hoverStartMs:  0

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
        // Usually anchored to arrival; deferred overflow cards receive the time
        // they first become visible so they still get a complete readable turn.
        interval: Math.max(400, fullInterval - (Date.now() - card.timeoutStartedAt) + card._hoverPausedMs)
        running:  shouldRun && !_cardHover.hovered
        onTriggered: card.dismiss(true)
    }

    property real _timeoutProgress: 1.0
    property real _countdownPulse:  1.0
    readonly property bool _showCountdown: card.visible && card.enabled
        && _autoClose.shouldRun && !ShellSettings.reduceMotion
    readonly property real _trueRemaining: Math.max(0, _autoClose.fullInterval - (Date.now() - card.timeoutStartedAt) + card._hoverPausedMs)

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
        value: _cardHover.hovered
        when: _countdownAnim.running
        restoreMode: Binding.RestoreNone
    }

    SequentialAnimation {
        running: card._showCountdown && card._timeoutProgress < 0.18 && !_cardHover.hovered
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
        width:  card.width
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

        // one Behavior drives both arrival and dismissal, so the curve has to follow the
        // direction — every other swap in the shell decelerates in and accelerates out
        Behavior on x       { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(200); easing.type: card._leaving ? Easing.InCubic : Easing.OutQuart } }
        Behavior on opacity { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(140) } }
        Behavior on height  { enabled: card.visible && cardRect._behaviorEnabled && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic } }

        // fill only — border lives in _cardBorder overlay so the shimmer's layer/clip can't cut its antialiased edges.
        // popup base: same opaque chrome tone as menu/calendar (and the bar's hue) so a standalone card reads as one family, not a lighter floating row.
        color: Theme.rowFill(_cardHover.hovered, card.isCritical)

        Behavior on color { ColorAnimation { duration: Motion.fast } }

        ClippingRectangle {
            visible: card.showIconSlot
            width: 24; height: 24
            radius: 6
            color: "transparent"
            anchors.top:        parent.top
            anchors.left:       parent.left
            anchors.topMargin:  13
            anchors.leftMargin: 14
            // The notification image wins when present; one texture item covers both cases.
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
            z: 2   // above _bodyArea so the action chips get their clicks
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
                    // Reserve the close affordance so long summaries never
                    // disappear beneath it.
                    anchors.rightMargin: 18
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

                Rectangle {
                    anchors.fill: parent
                    radius: _previewClip.radius
                    color: "transparent"
                    antialiasing: true
                    border.width: 1
                    border.color: Theme.menuControlLine
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
                        border.width: 1
                        border.color: (_actMa.containsMouse || _actMa.pressed)
                            ? Theme.withAlpha(_tint, 0.50)
                            : Theme.withAlpha(_tint, 0.22)
                        Behavior on color        { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: _actBtn.modelData.text
                        Accessible.onPressAction: card.invokeAction(_actBtn.modelData)

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
                            onClicked: card.invokeAction(_actBtn.modelData)
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
                // Middle-click is a non-destructive "take me to the source".
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
            border.width: 1
            border.color: _closeHover.hovered ? Theme.withAlpha(Theme.error, 0.32) : Theme.menuControlLine
            // Keep a quiet close affordance discoverable for touch/tablet
            // input, where a hover-only control can never be revealed.
            opacity: _cardHover.hovered ? 1.0 : 0.48
            scale:   _cardHover.hovered ? 1.0 : 0.90
            transformOrigin: Item.Center
            z: 2
            Behavior on opacity      { NumberAnimation { duration: Motion.fast } }
            Behavior on scale        { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on color        { ColorAnimation  { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation  { duration: Motion.fast } }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"
            Accessible.onPressAction: card.dismiss()
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

    PerimeterProgress {
        anchors.fill: cardRect
        visible: card._showCountdown
        opacity: cardRect.opacity * card._countdownPulse
        inset:        2.5
        cornerRadius: cardRect.radius
        progress:     card._timeoutProgress
        trackColor:   Theme.menuControlLine
        arcColor:     card.isCritical ? Theme.error
                    : (card._timeoutProgress < 0.30 ? Theme.warning : Theme.accent)
    }
}
