pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"
import "controls"

PageShell {
    id: root

    required property int viewportHeight

    implicitHeight: viewportHeight
    onPageShown: _timeTick++

    property bool _clearing: false
    property bool _clearArmed: false
    property int _timeTick: 0

    Timer {
        interval: 60000
        repeat: true
        running: root.active && MenuState.open && !Idle.isIdle
        onTriggered: root._timeTick++
    }

    Timer { id: _clearArmTimer; interval: 3000; onTriggered: root._clearArmed = false }
    onPageHidden: {
        _clearArmTimer.stop()
        root._clearArmed = false
    }

    function formatTime(ms): string {
        const value = Number(ms || Date.now())
        const diff = Math.max(0, Date.now() - value)
        if (diff < 60000)   return "just now"
        if (diff < 3600000) return Math.floor(diff / 60000) + "m"

        const d = new Date(value)
        const now = new Date()
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const age = today - day
        if (age <= 0 && diff < 86400000) return Math.floor(diff / 3600000) + "h"
        if (age < 172800000) return "Yesterday"
        if (age < 604800000) return Qt.formatDateTime(d, "ddd")
        return Qt.formatDateTime(d, "MMM d")
    }

    function dayKey(ms): string {
        const d = new Date(Number(ms || Date.now()))
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function sectionLabel(ms): string {
        const value = Number(ms || Date.now())
        const d = new Date(value)
        const now = new Date()
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const age = today - day
        if (age <= 0) return "Today"
        if (age < 172800000) return "Yesterday"
        if (age < 604800000) return Qt.formatDateTime(d, "dddd")
        return Qt.formatDateTime(d, "MMM d, yyyy")
    }

    function requestClearAll(): void {
        if (_clearing || Notifications.historyCount === 0) return
        if (_clearArmed) { _clearArmed = false; _clearArmTimer.stop(); clearAll() }
        else { _clearArmed = true; _clearArmTimer.restart() }
    }

    function clearAll(): void {
        if (_clearing || Notifications.historyCount === 0) return
        // release focus before the tab-focus binding turns off or Qt warns and retains it
        if (_clearButton.activeFocus) root.forceActiveFocus()
        if (ShellSettings.reduceMotion) {
            Notifications.clearHistory()
            return
        }
        _clearing = true
        _clearAllAnimation.restart()
    }

    SequentialAnimation {
        id: _clearAllAnimation
        NumberAnimation {
            target: _historyList
            property: "opacity"
            to: 0
            duration: Motion.fast
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                Notifications.clearHistory()
                _historyList.opacity = 1
                root._clearing = false
            }
        }
    }

    Item {
        id: _pageSurface
        width: parent.width
        height: root.viewportHeight

        Item {
            id: _header
            width: parent.width
            height: 38

            ShellText {
                id: _headerTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Math.min(implicitWidth,
                    (_clearButton.visible ? _clearButton.x - 10 : _header.width)
                    - (_countChip.visible ? _countChip.width + 9 : 0)))
                text: "Notifications"
                color: Theme.text
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                id: _countChip
                anchors.left: _headerTitle.right
                anchors.leftMargin: 9
                anchors.verticalCenter: _headerTitle.verticalCenter
                visible: Notifications.hasHistory
                width:  Math.max(18, _countTxt.implicitWidth + 12)
                height: 18
                radius: 9
                antialiasing: true
                color: Theme.withAlpha(Theme.subtext, 0.12)

                ShellText {
                    id: _countTxt
                    anchors.centerIn: parent
                    text: String(Notifications.historyCount)
                    color: Theme.withAlpha(Theme.text, 0.62)
                    font.pixelSize: Settings.fontSize - 3
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: _clearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifications.hasHistory
                width: visible ? (root._clearArmed ? 92 : 68) : 0
                height: 30
                radius: Theme.radiusControl
                antialiasing: true
                activeFocusOnTab: visible
                onVisibleChanged:     if (!visible) root._clearArmed = false
                onActiveFocusChanged: if (!activeFocus) root._clearArmed = false

                color: root._clearArmed
                    ? Theme.withAlpha(Theme.error, _clearTap.pressed ? 0.28 : 0.16)
                    : _clearTap.pressed ? Theme.withAlpha(Theme.error, 0.20)
                    : _clearHover.hovered ? Theme.withAlpha(Theme.subtext, 0.16) : Theme.menuControl
                opacity: root._clearing ? 0.45 : 1.0

                OutlineBorder {
                    radius: _clearButton.radius
                    outlineWidth: (_clearButton.activeFocus || root._clearArmed) ? 2 : 1
                    outlineColor: root._clearArmed
                        ? Theme.withAlpha(Theme.error, Theme.focusRingAlpha)
                        : _clearButton.activeFocus ? Theme.withAlpha(Theme.error, Theme.focusRingAlpha)
                        : _clearHover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Clear all notifications"
                Accessible.description: root._clearArmed ? "Activate again to confirm" : ""
                Accessible.onPressAction: root.requestClearAll()
                Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.requestClearAll(); event.accepted = true }
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.requestClearAll(); event.accepted = true }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.requestClearAll(); event.accepted = true }
                Keys.onEscapePressed: event => { if (root._clearArmed) { root._clearArmed = false; event.accepted = true } else event.accepted = false }

                MotionBehavior on width {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                ColorFade on color {}
                MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                HoverHandler { id: _clearHover; enabled: !root._clearing; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { id: _clearTap; enabled: !root._clearing; onTapped: root.requestClearAll() }

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    ShellText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰆴"
                        color: root._clearArmed ? Theme.error
                            : _clearHover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.72)
                        font.pixelSize: Settings.fontSize
                        ColorFade on color {}
                    }
                    ShellText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._clearArmed ? "Confirm?" : "Clear"
                        color: root._clearArmed ? Theme.error
                            : _clearHover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.text, 0.76)
                        font.pixelSize: Settings.fontSize - 2
                        font.weight: root._clearArmed ? Font.DemiBold : Font.Normal
                        ColorFade on color {}
                    }
                }
            }
        }

        Item {
            width: parent.width
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            visible: !Notifications.hasHistory
            Accessible.role: Accessible.StaticText
            Accessible.name: "No notifications"

            Column {
                anchors.centerIn: parent
                spacing: 7

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48
                    height: 48
                    radius: 24
                    antialiasing: true
                    color: Theme.withAlpha(Theme.subtext, 0.07)

                    OutlineBorder {
                        radius: 24
                        outlineColor: Theme.menuCardBorder
                    }

                    ShellText {
                        anchors.centerIn: parent
                        text: "󰂛"
                        color: Theme.withAlpha(Theme.subtext, 0.34)
                        font.pixelSize: 24
                    }
                }

                Item { width: 1; height: 2 }

                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "All caught up"
                    color: Theme.withAlpha(Theme.text, 0.78)
                    font.pixelSize: Settings.fontSize + 1
                    font.weight: Font.Medium
                }
            }
        }

        ListView {
            id: _historyList
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: parent.width
            spacing: 8
            visible: Notifications.hasHistory
            clip: true
            boundsMovement: Flickable.StopAtBounds
            flickDeceleration: 1800
            maximumFlickVelocity: 2200
            cacheBuffer: 120
            model: Notifications.historyModel

            delegate: Item {
                    id: _entry
                    // a ListModel delegate gets roles, not modelData; alias so the rest of the entry reads the same
                    required property var model
                    readonly property var modelData: model
                    required property int index

                    readonly property bool _critical: Number(modelData.urgency) === 2
                    readonly property string _appIconSource: Notifications.appIconSource(
                        modelData.appIcon, modelData.desktopEntry, modelData.appName)
                    readonly property bool _showSection: index === 0
                        || root.dayKey(modelData.time) !== root.dayKey(Notifications.historyModel.get(index - 1)?.time)
                    readonly property int _sectionHeight: _showSection ? 26 : 0
                    readonly property int _cardHeight: Math.max(70, _entryContent.implicitHeight + 20)
                    readonly property int _fullHeight: _sectionHeight + _cardHeight
                    property bool _removing: false
                    property bool _expanded: false
                    property var _pendingRemove: null

                    function _toggleExpand(): void {
                        if (_expanded) _expanded = false
                        else if (_body.truncated) _expanded = true
                    }

                    width: _historyList.width
                    height: _removing ? 0 : _fullHeight
                    opacity: _removing ? 0 : 1
                    clip: true

                    MotionBehavior on height {
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.InCubic }
                    }
                    MotionBehavior on opacity {
                        NumberAnimation { duration: Motion.fast }
                    }

                    function removeSelf(): void {
                        if (_removing || root._clearing) return
                        // plain values: a ListModel row belongs to its delegate and shifts if a notif lands mid-animation
                        const key = { time: _entry.modelData.time, summary: _entry.modelData.summary }
                        if (ShellSettings.reduceMotion) {
                            Notifications.removeFromHistory(key)
                            return
                        }
                        _pendingRemove = key
                        _removing = true
                        _removeTimer.restart()
                    }

                    Timer {
                        id: _removeTimer
                        interval: Motion.fast + 35
                        onTriggered: {
                            if (_entry._pendingRemove !== null)
                                Notifications.removeFromHistory(_entry._pendingRemove)
                            _entry._pendingRemove = null
                        }
                    }

                    Item {
                        visible: _entry._showSection
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        height: _entry._sectionHeight

                        ShellText {
                            id: _secText
                            anchors.left:           parent.left
                            anchors.leftMargin:     4
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root._timeTick; return root.sectionLabel(_entry.modelData.time) }
                            color: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.22), 0.74)
                            font.pixelSize: Settings.fontSize - 3
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.4
                        }

                        Hairline {
                            anchors.left:           _secText.right
                            anchors.leftMargin:     10
                            anchors.right:          parent.right
                            anchors.verticalCenter: _secText.verticalCenter
                            color:  Theme.withAlpha(Theme.subtext, 0.10)
                        }
                    }

                    Rectangle {
                        id: _card
                        x: 0
                        y: _entry._sectionHeight
                        width: parent.width
                        height: _entry._cardHeight
                        radius: Theme.radiusControl
                        antialiasing: true
                        clip: true
                        color: Theme.rowFill(_entryHover.hovered, _entry._critical)

                        OutlineBorder {
                            radius: _card.radius
                            outlineWidth: _card.activeFocus ? 2 : 1
                            outlineColor: _card.activeFocus
                                ? Theme.withAlpha(_entry._critical ? Theme.error : Theme.accent, Theme.focusRingAlpha)
                                : _entry._critical ? Theme.withAlpha(Theme.error, 0.50)
                                : Theme.menuCardBorder
                            ColorFade on outlineColor {}
                        }

                        ColorFade on color {}
                        HoverHandler {
                            id: _entryHover
                            cursorShape: (_body.truncated || _entry._expanded) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            enabled: !root._clearing && !_entry._removing
                            onTapped: eventPoint => {
                                const p = _removeButton.mapFromItem(_card, eventPoint.position.x, eventPoint.position.y)
                                if (p.x >= -4 && p.x <= _removeButton.width + 4 &&
                                    p.y >= -4 && p.y <= _removeButton.height + 4) return
                                _entry._toggleExpand()
                            }
                        }

                        activeFocusOnTab: _body.truncated || _entry._expanded
                        Accessible.role: activeFocusOnTab ? Accessible.Button : Accessible.StaticText
                        Accessible.name: String(_entry.modelData.summary || "Notification")
                        Accessible.description: activeFocusOnTab
                            ? (_entry._expanded ? "Activate to collapse" : "Activate to expand") : ""
                        Accessible.onPressAction: _entry._toggleExpand()
                        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _entry._toggleExpand(); event.accepted = true }
                        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _entry._toggleExpand(); event.accepted = true }
                        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _entry._toggleExpand(); event.accepted = true }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: _entry._critical ? 3 : 0
                            height: 30
                            radius: 1.5
                            color: Theme.error
                        }

                        Column {
                            id: _entryContent
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Row {
                                width: parent.width
                                spacing: 7

                                IconImage {
                                    id: _appIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: _entry._appIconSource.length > 0
                                    width: visible ? 16 : 0
                                    height: 16
                                    // without this the themed icon decodes at its native size (often 256px+) to paint 16px
                                    implicitSize: 16
                                    source: _entry._appIconSource
                                    asynchronous: true
                                }

                                ShellText {
                                    id: _appName
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - _entryTime.implicitWidth
                                        - parent.spacing - 28
                                        - (_appIcon.visible ? _appIcon.width + parent.spacing : 0))
                                    text: _entry.modelData.appName || "Notification"
                                    color: _entry._critical ? Theme.error : Theme.withAlpha(Theme.subtext, 0.70)
                                    font.pixelSize: Settings.fontSize - 2
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                ShellText {
                                    id: _entryTime
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: { root._timeTick; return root.formatTime(_entry.modelData.time) }
                                    color: Theme.withAlpha(Theme.subtext, 0.42)
                                    font.pixelSize: Settings.fontSize - 3
                                }
                            }

                            ShellText {
                                width: parent.width
                                rightPadding: 28
                                text: _entry.modelData.summary || "Notification"
                                color: Theme.text
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            ShellText {
                                id: _body
                                width: parent.width
                                visible: text.length > 0
                                text: _entry.modelData.body || ""
                                color: Theme.withAlpha(Theme.text, 0.58)
                                font.pixelSize: Settings.fontSize - 1
                                wrapMode: Text.WordWrap
                                maximumLineCount: _entry._expanded ? 12 : 2
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: _removeButton
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            width: 24
                            height: 24
                            radius: 12
                            antialiasing: true
                            activeFocusOnTab: true
                            z: 2

                            color: _removeTap.pressed
                                ? Theme.withAlpha(Theme.error, 0.24)
                                : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.17) : Theme.withAlpha(Theme.subtext, 0.08)
                            opacity: _entryHover.hovered || activeFocus ? 1.0 : 0.62
                            scale: _entryHover.hovered || activeFocus ? 1.0 : 0.94

                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + String(_entry.modelData.summary || "notification")
                            Accessible.onPressAction: _entry.removeSelf()
                            Keys.onSpacePressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }
                            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }
                            Keys.onEnterPressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }

                            ColorFade on color {}
                            MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

                            OutlineBorder {
                                radius: _removeButton.radius
                                outlineWidth: _removeButton.activeFocus ? 2 : 1
                                outlineColor: _removeButton.activeFocus
                                    ? Theme.withAlpha(Theme.error, Theme.focusRingAlpha)
                                    : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.36) : Theme.menuControlLine
                                ColorFade on outlineColor {}
                            }
                            MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                            HoverHandler { id: _removeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: _removeTap; enabled: !root._clearing && !_entry._removing; onTapped: _entry.removeSelf() }

                            ShellText {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: _removeHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.56)
                                font.pixelSize: Settings.fontSize - 2
                            }
                        }
                    }
            }
        }

        ListEdgeLines {
            anchors.fill: _historyList
            visible: Notifications.hasHistory
            opacity: _historyList.opacity
            z: 2
            list: _historyList
            maxOpacity: 0.72
        }

        MenuScrollThumb {
            list: _historyList
            fadeMultiplier: _historyList.opacity
            trackInset: 4
            rightInset: 2
            shown: Notifications.hasHistory
            z: 3
        }
    }
}
