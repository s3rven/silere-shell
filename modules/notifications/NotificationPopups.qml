import QtQuick
import Quickshell
import "../../config"
import "../../services"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    screen:         targetScreen
    color:          "transparent"
    exclusiveZone:  -1

    readonly property int _cardW: 320
    // Reserve so a floating card's drop shadow isn't clipped at the window edge.
    readonly property int _shadowPad: (ShellSettings.barFloating && ShellSettings.barShadow) ? 22 : 0
    // The side gap a floating bar leaves (mirrors Bar.qml's surfaceWidth math); the
    // card's outer edge lines up with the bar's edge instead of hugging the screen
    // corner. Plain margin when the bar isn't floating.
    readonly property real _barSideGap: ShellSettings.barFloating && targetScreen
        ? 4 * Math.round(targetScreen.width * (1.0 - ShellSettings.barWidth) / 8)
        : 0
    readonly property real _edgeMargin: ShellSettings.barFloating ? Math.max(0, _barSideGap) : 10

    implicitWidth:  _cardW + 24 + _shadowPad
    implicitHeight: Math.max(1, outerCol.implicitHeight + 12 + _shadowPad)

    // Unmap the surface while nothing is showing (same pattern as MenuWindow /
    // OsdWindow) instead of holding a mapped transparent strip at rest. Safe
    // across exit animations: a card's peel finishes before dismissRequested
    // shrinks the model, so the count hits zero only after the last card is out.
    visible: ShellSettings.notifPopupEnabled && Notifications.activeCount > 0

    // Corner, Settings → Notify. Drives the window anchor, the card alignment, and
    // which way cards slide in (centre fades with no slide).
    readonly property string _pos:     ShellSettings.notifPosition
    readonly property bool   _left:     _pos === "top-left"
    readonly property bool   _center:   _pos === "top-center"
    readonly property int    _slideDir: _center ? 0 : (_left ? -1 : 1)
    readonly property bool   _barBottom: ShellSettings.barPosition === "bottom"

    anchors {
        top:    !win._barBottom
        bottom: win._barBottom
        left:   win._left
        right:  !win._left && !win._center
    }

    margins {
        // +4 mirrors Bar.qml's surfaceInset so popups clear a floating bar.
        top:    win._barBottom ? 6
            : (ShellSettings.barFloating ? 4 : 0) + ShellSettings.barHeight + 6
        bottom: win._barBottom
            ? (ShellSettings.barFloating ? 4 : 0) + ShellSettings.barHeight + 6 : 0
        // _shadowPad backed out here, then re-added by outerCol's inset, so the
        // visible card edge still lands at _edgeMargin from the screen edge.
        right: win._pos === "top-right" ? Math.max(0, win._edgeMargin - win._shadowPad) : 0
        left:  win._left              ? Math.max(0, win._edgeMargin - win._shadowPad) : 0
    }
    mask: Region { item: outerCol }

    // When > 0, we're in dismiss-all mode: each card animates out individually,
    // and only after the last one fires dismissRequested do we clear the model.
    // Set after counting non-null delegates to avoid a stuck counter if itemAt returns null.
    property int _pendingDismissAll: 0
    property var _pendingDismissItems: []

    function _forgetPendingDismiss(id: int, notification): void {
        const next = []
        for (let i = 0; i < win._pendingDismissItems.length; i++) {
            const it = win._pendingDismissItems[i]
            if (!(it.id === id && it.notification === notification)) next.push(it)
        }
        win._pendingDismissItems = next
        win._pendingDismissAll = next.length
        if (next.length === 0) _cascadeSafety.stop()
    }

    function _dismissPendingSnapshot(): void {
        const items = win._pendingDismissItems
        win._pendingDismissItems = []
        win._pendingDismissAll = 0
        for (let i = 0; i < items.length; i++)
            Notifications.dismissObject(items[i].id, items[i].notification)
    }

    // Dismiss-all plays as a top-to-bottom cascade, one card peels off per tick
    // instead of all at once. reduceMotion skips straight to a bulk clear.
    property var _cascadeItems: []
    property int _cascadeIdx:   0
    Timer {
        id: _cascadeTimer
        interval: 45
        repeat:   true
        triggeredOnStart: true
        onTriggered: {
            if (win._cascadeIdx >= win._cascadeItems.length) {
                running = false
                win._cascadeItems = []
                // Don't clear the model here — each card finishes its own peel.
                // The fallback covers a card that never reports back.
                if (win._pendingDismissAll > 0) _cascadeSafety.restart()
                return
            }
            const it = win._cascadeItems[win._cascadeIdx]
            if (it) it.dismiss()
            win._cascadeIdx++
        }
    }

    // Safety net: if the per-card dismissRequested chain doesn't drain the
    // counter, clear what's left. Outlasts a card's exit animation.
    Timer {
        id: _cascadeSafety
        interval: Math.max(400, Motion.ms(280) + 150)
        onTriggered: {
            if (win._pendingDismissAll > 0) win._dismissPendingSnapshot()
        }
    }

    Column {
        id: outerCol
        anchors {
            top:    win._barBottom ? undefined : parent.top
            bottom: win._barBottom ? parent.bottom : undefined
            right:  parent.right
            left:   parent.left
            // Shadow pad goes on the far edge so the drop shadow has room to bleed
            // inside the window rather than clipping at the bar-facing edge.
            topMargin:    win._barBottom ? 0 : 6
            bottomMargin: win._barBottom ? 6 : 0
            rightMargin: (win._left || win._center) ? 0 : win._shadowPad
            leftMargin:  win._left ? win._shadowPad : 0
        }
        spacing: 6

        Item {
            id: _dismissBar
            property bool shown: Notifications.activeCount > 1
            width:   parent.width
            height:  shown ? 30 : 0
            clip:    true
            enabled: shown
            visible: height > 0.5

            Behavior on height {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: _pillRect
                anchors.right:            (win._left || win._center) ? undefined : parent.right
                anchors.left:             win._left   ? parent.left : undefined
                anchors.horizontalCenter: win._center ? parent.horizontalCenter : undefined
                y:       _dismissBar.shown ? 4 : 14
                opacity: _dismissBar.shown ? 1.0 : 0.0

                Behavior on y       { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                height: 24
                width:  _pillRow.implicitWidth + 22
                radius: height / 2          // full pill, not a slightly-rounded box
                antialiasing: true
                // Press darkens the fill/border rather than scaling, scaling the
                // pill would blur the NativeRendering text inside it.
                color: _dismissPress.pressed
                    ? Theme.withAlpha(Theme.error, 0.22)
                    : _pillHover.hovered
                        ? Theme.withAlpha(Theme.error, 0.12)
                        : Theme.surface
                border.width: 1
                border.color: _dismissPress.pressed
                    ? Theme.withAlpha(Theme.error, 0.60)
                    : _pillHover.hovered
                        ? Theme.withAlpha(Theme.error,   0.38)
                        : Theme.withAlpha(Theme.subtext, 0.20)

                Behavior on color        { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Row {
                    id: _pillRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:           "󰆴"
                        color:          _pillHover.hovered ? Theme.withAlpha(Theme.error, 0.85) : Theme.withAlpha(Theme.subtext, 0.45)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:           "Dismiss all"
                        color:          _pillHover.hovered ? Theme.withAlpha(Theme.error, 0.85) : Theme.withAlpha(Theme.subtext, 0.65)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize - 1
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }

                HoverHandler { id: _pillHover }
                TapHandler {
                    id: _dismissPress
                    cursorShape: Qt.PointingHandCursor
                    onTapped: {
                        var items = []
                        var pending = []
                        for (var i = 0; i < stack.count; i++) {
                            var it = stack.itemAt(i)
                            if (it) {
                                items.push(it)
                                pending.push({ id: it.notifId, notification: it.notification })
                            }
                        }
                        if (items.length === 0) { Notifications.dismissAll(); return }
                        win._pendingDismissItems = pending
                        win._pendingDismissAll = pending.length
                        if (ShellSettings.reduceMotion) {
                            for (var j = 0; j < items.length; j++) items[j].dismiss()
                            return
                        }
                        win._cascadeItems = items
                        win._cascadeIdx   = 0
                        _cascadeTimer.restart()
                    }
                }
            }
        }

        Repeater {
            id: stack
            model: Notifications.popupModel

            NotificationCard {
                required property var modelData
                required property int index

                notification: modelData
                notifId:      modelData.id
                createdAt:    Notifications.timeFor(modelData.id)
                slideDir:     win._slideDir

                anchors.right:            (win._left || win._center) ? undefined : parent.right
                anchors.left:             win._left   ? parent.left : undefined
                anchors.horizontalCenter: win._center ? parent.horizontalCenter : undefined

                // Cap the stack, extra cards still exist (and still auto-dismiss),
                // they're just hidden behind the "· N more" chip below.
                visible: ShellSettings.notifMaxVisible <= 0 || index < ShellSettings.notifMaxVisible

                onDismissRequested: (id, notification, expired) => {
                    if (win._pendingDismissAll > 0) {
                        Notifications.dismissObject(id, notification, expired)
                        win._forgetPendingDismiss(id, notification)
                    } else {
                        Notifications.dismissObject(id, notification, expired)
                    }
                }
            }
        }

        Item {
            id: _moreChip
            readonly property int _extra: ShellSettings.notifMaxVisible > 0
                ? Math.max(0, Notifications.activeCount - ShellSettings.notifMaxVisible) : 0
            width:   parent.width
            height:  _extra > 0 ? 22 : 0
            visible: height > 0.5
            clip:    true
            Behavior on height { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.right:            (win._left || win._center) ? undefined : parent.right
                anchors.left:             win._left   ? parent.left : undefined
                anchors.horizontalCenter: win._center ? parent.horizontalCenter : undefined
                anchors.verticalCenter:   parent.verticalCenter
                width:  _moreTxt.implicitWidth + 16
                height: 18
                radius: 9
                antialiasing: true
                color: Theme.withAlpha(Theme.surface, 0.97)
                border.width: 1
                border.color: Theme.withAlpha(Theme.subtext, 0.18)
                Text {
                    id: _moreTxt
                    anchors.centerIn: parent
                    text: "· " + _moreChip._extra + " more"
                    color: Theme.withAlpha(Theme.subtext, 0.7)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
