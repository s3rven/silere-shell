pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    WlrLayershell.namespace: "silere-notifications"

    screen:         targetScreen
    color:          "transparent"
    exclusiveZone:  -1

    readonly property int _shadowPad: ShellSettings.barShadow ? 16 : 0
    // the body wraps at 3 lines collapsed, so a card pinned at 320 elides sooner as type grows
    readonly property int _cardW: Math.max(180, Math.min(
        Metrics.snap4(320 * Settings.fontSize / 12),
        targetScreen ? targetScreen.width - 24 - _shadowPad : 320))
    readonly property bool _hasBar: Metrics.barPresent(targetScreen)
    readonly property real _barSideGap: ShellSettings.barFloating && _hasBar && targetScreen
        ? 4 * Math.round(targetScreen.width * (1.0 - ShellSettings.barWidth) / 8)
        : 0
    readonly property real _edgeMargin: ShellSettings.barFloating && _hasBar ? Math.max(0, _barSideGap) : 10
    readonly property int _barClearance: Metrics.popupClearanceOn(targetScreen, 6)
    readonly property int _availableH: targetScreen
        ? Math.max(64, Math.floor(targetScreen.height - _barClearance - 12)) : 640
    readonly property int _availableContentH: Math.max(48,
        _availableH - 12 - _shadowPad)

    implicitWidth:  _cardW + 24 + _shadowPad
    // quantized: every implicitHeight change reconfigures the layer surface, and arrival/dismiss animates height for ~160ms
    readonly property int _contentH: Math.max(1, outerCol.implicitHeight + 12 + _shadowPad)
    implicitHeight: Math.min(_availableH,
        Math.max(64, Math.ceil(win._contentH / 64) * 64))

    readonly property string _pos:     ShellSettings.notifPosition
    readonly property bool   _left:     _pos === "top-left"
    readonly property bool   _center:   _pos === "top-center"
    readonly property int    _slideDir: _center ? 0 : (_left ? -1 : 1)
    readonly property bool   _barBottom: ShellSettings.barPosition === "bottom"

    function _alignedX(containerWidth: real, itemWidth: real): real {
        if (win._left) return 0
        if (win._center) return Math.round((containerWidth - itemWidth) / 2)
        return containerWidth - itemWidth
    }

    // inline components can't reach the enclosing file's ids, so alignment arrives as flags
    component NotifChip: Item {
        id: chip

        property bool shown: false
        property bool alignLeft: false
        property bool alignCenter: false
        property string glyph: ""
        property string label: ""
        property color tint: Theme.accent
        readonly property bool pressed: _tap.pressed

        signal triggered()

        width:   parent ? parent.width : 0
        height:  shown ? 30 : 0
        clip:    true
        enabled: shown
        visible: height > 0.5

        Disclosure on height { expanded: chip.shown }

        Rectangle {
            id: _surface
            x: chip.alignLeft ? 0
                : chip.alignCenter ? Math.round((parent.width - width) / 2)
                : parent.width - width
            anchors.verticalCenter: parent.verticalCenter
            width:  _row.implicitWidth + 20
            height: 24
            radius: 12
            antialiasing: true
            // the popup window is transparent, so an alpha tint would let the desktop through - blend into the base
            color: chip.pressed ? Theme.mix(Theme.menuControl, chip.tint, 0.26)
                : _hover.hovered ? Theme.mix(Theme.menuControl, chip.tint, 0.15) : Theme.menuControl

            ColorFade on color {}

            OutlineBorder {
                radius: _surface.radius
                outlineWidth: 1
                outlineColor: _hover.hovered
                    ? Theme.withAlpha(chip.tint, 0.42) : Theme.menuControlLine
                ColorFade on outlineColor {}
            }

            Accessible.role: Accessible.Button
            Accessible.name: chip.label
            Accessible.focusable: chip.shown
            Accessible.onPressAction: chip.triggered()

            HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }
            TapHandler   { id: _tap; onTapped: chip.triggered() }

            Row {
                id: _row
                anchors.centerIn: parent
                spacing: 5

                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.glyph
                    color: _hover.hovered ? chip.tint
                        : Theme.withAlpha(Theme.menuTextMuted, 0.76)
                    font.pixelSize: Settings.fontLabel
                    ColorFade on color {}
                }

                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    color: _hover.hovered ? Theme.withAlpha(Theme.text, 0.90)
                        : Theme.withAlpha(Theme.menuTextMuted, 0.86)
                    font.pixelSize: Settings.fontCaption
                    font.weight: Font.Medium
                    ColorFade on color {}
                }
            }
        }
    }

    anchors {
        top:    !win._barBottom
        bottom: win._barBottom
        left:   win._left
        right:  !win._left && !win._center
    }

    margins {
        top:    win._barBottom ? 6 : Metrics.popupClearanceOn(win.targetScreen, 2)
        bottom: win._barBottom ? Metrics.popupClearanceOn(win.targetScreen, 2) : 0
        right: win._pos === "top-right" ? Math.max(0, win._edgeMargin - win._shadowPad) : 0
        left:  win._left              ? Math.max(0, win._edgeMargin - win._shadowPad) : 0
    }
    mask: Region { item: outerCol }

    property var _pendingDismissItems: []
    readonly property int _pendingDismissAll: _pendingDismissItems.length
    property bool _showAll: false
    property int _batchExits: 0
    readonly property bool _dismissing: win._pendingDismissAll > 0 || _cascadeTimer.running

    property bool _quietPaint: false

    readonly property int _visibleCards: win._showAll || ShellSettings.notifMaxVisible <= 0
        ? stack.count : Math.min(stack.count, ShellSettings.notifMaxVisible)

    function _noteLeaving(): void {
        win._quietPaint = true
        _quietPaintHold.restart()
    }

    Timer {
        id: _quietPaintHold
        interval: Motion.ms(210) + 90
        onTriggered: win._quietPaint = false
    }

    function revealAll(): void {
        if (Notifications.activeCount > 0) win._showAll = true
    }

    function dismissAll(): void {
        if (win._dismissing) return

        const pending = []
        const inSnapshot = ({})
        const live = Notifications.list || []
        for (let n = 0; n < live.length; n++) {
            const entry = live[n]
            if (!entry || !entry.notification) continue
            pending.push({ id: entry.id, notification: entry.notification })
            inSnapshot[entry.id] = true
        }
        if (pending.length === 0) return

        // a card outside the snapshot can never report its exit, so counting it leaves the batch one short
        const items = []
        for (let i = 0; i < stack.count; i++) {
            const slot = stack.itemAt(i)
            if (!slot || !slot.cardItem || inSnapshot[slot.modelData.id] !== true) continue
            slot.cardItem.collapseOnDismiss = false
            items.push(slot.cardItem)
        }

        win._pendingDismissItems = pending
        win._batchExits = items.length
        if (items.length === 0) { win._dismissPendingSnapshot(); return }
        if (ShellSettings.reduceMotion) {
            for (let j = 0; j < items.length; j++) items[j].dismiss()
            _cascadeSafety.restart()
            return
        }
        win._cascadeItems = items
        win._cascadeIdx = 0
        _cascadeTimer.restart()
    }

    Connections {
        target: Notifications
        function onActiveCountChanged(): void {
            if (ShellSettings.notifMaxVisible > 0
                    && Notifications.activeCount <= ShellSettings.notifMaxVisible)
                win._showAll = false
        }
    }

    Connections {
        target: ShellSettings
        function onNotifMaxVisibleChanged(): void { win._showAll = false }
    }

    // removing a card the moment its own exit ends snaps the still-animating cards below it upward
    function _noteBatchExit(): void {
        if (win._batchExits <= 0) return
        win._batchExits--
        if (win._batchExits > 0) return
        _cascadeSafety.stop()
        win._dismissPendingSnapshot()
    }

    function _dismissPendingSnapshot(): void {
        const items = win._pendingDismissItems
        win._pendingDismissItems = []
        win._batchExits = 0
        for (let i = 0; i < items.length; i++)
            Notifications.dismissObject(items[i].id, items[i].notification, false)
    }

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
                // don't clear the model here — each card finishes its own peel
                if (win._pendingDismissAll > 0) _cascadeSafety.restart()
                return
            }
            const it = win._cascadeItems[win._cascadeIdx]
            if (it) it.dismiss()
            win._cascadeIdx++
        }
    }

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
            topMargin:    win._barBottom ? 0 : 6
            bottomMargin: win._barBottom ? 6 : 0
            rightMargin: (win._left || win._center) ? 0 : win._shadowPad
            leftMargin:  win._left ? win._shadowPad : 0
        }
        spacing: 6

        NotifChip {
            id: _clearChip
            shown:          Notifications.activeCount > 1 || win._dismissing
            alignLeft:      win._left
            alignCenter:    win._center
            glyph:          "󰆴"
            label:          "Clear all"
            tint:           Theme.error
            onTriggered:    win.dismissAll()
        }

        Item {
            id: _cardViewport
            width: parent.width
            visible: height > 0.5
            height: Math.min(cardCol.implicitHeight, Math.max(48,
                win._availableContentH - _clearChip.height - _moreChip.height
                - outerCol.spacing * 2))

            HoverHandler { id: _stackHover }

            ShellFlickable {
                id: _cardScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: cardCol.implicitHeight
                interactive: contentHeight > height + 1

                Column {
                    id: cardCol
                    width: _cardScroll.width
                    spacing: 0

                    Repeater {
                        id: stack
                        model: Notifications.popupModel

                        Item {
                            id: _slot
                            required property var modelData
                            required property int index

                            readonly property bool shouldLoad: win._showAll
                                || ShellSettings.notifMaxVisible <= 0
                                || index < ShellSettings.notifMaxVisible
                            readonly property var cardItem: _cardLoader.item
                            property real timeoutStartedAt: 0
                            readonly property real _gap: index < win._visibleCards - 1 ? 6 : 0

                            width: win._cardW
                            height: cardItem
                                ? cardItem.implicitHeight + _gap * cardItem.collapseRatio : 0
                            visible: shouldLoad

                            x: win._alignedX(parent.width, width)

                            Component.onCompleted: {
                                if (shouldLoad) timeoutStartedAt = Notifications.updateTimeFor(modelData.id)
                            }
                            onShouldLoadChanged: {
                                if (shouldLoad) timeoutStartedAt = Date.now()
                                else timeoutStartedAt = 0
                            }

                            Connections {
                                target: Notifications
                                function onContentUpdated(notifId: int): void {
                                    if (notifId === _slot.modelData.id && _slot.shouldLoad)
                                        _slot.timeoutStartedAt = Date.now()
                                }
                            }

                            Loader {
                                id: _cardLoader
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: _slot.cardItem ? _slot.cardItem.implicitHeight : 0
                                active: _slot.shouldLoad && _slot.timeoutStartedAt > 0

                                sourceComponent: NotificationCard {
                                    notification: _slot.modelData
                                    notifId: _slot.modelData.id
                                    createdAt: Notifications.timeFor(_slot.modelData.id)
                                    timeoutStartedAt: _slot.timeoutStartedAt
                                    slideDir: win._slideDir
                                    quietPaint: win._quietPaint
                                    stackSize: win._visibleCards
                                    stackHovered: _stackHover.hovered

                                    onLeaving: win._noteLeaving()

                                    onDismissRequested: (id, notification, expired) => {
                                        if (win._batchExits > 0
                                                && win._pendingDismissItems.some(it => it.id === id)) {
                                            win._noteBatchExit()
                                            return
                                        }
                                        Notifications.dismissObject(id, notification, expired)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ListEdgeLines {
                anchors.fill: _cardScroll
                visible: _cardScroll.interactive
                list: _cardScroll
            }
        }

        NotifChip {
            id: _moreChip
            readonly property int _extra: !win._showAll && ShellSettings.notifMaxVisible > 0
                ? Math.max(0, Notifications.activeCount - ShellSettings.notifMaxVisible) : 0
            shown:          _extra > 0
            alignLeft:      win._left
            alignCenter:    win._center
            glyph:          "󰂚"
            label:          "Show " + _extra + " more"
            onTriggered:    win.revealAll()
        }
    }
}
