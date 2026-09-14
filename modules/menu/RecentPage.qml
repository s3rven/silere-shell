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
    onPageShown: root._touchNow()

    readonly property string filter: MenuState.recentFilter
    readonly property int rowCount: _filtered.count

    // a reassigned list model resets the view, so the rail filters through a mirror that
    // is reconciled row by row and leaves an untouched row's delegate alone
    FilteredHistory {
        id: _filtered
        source: Notifications.historyModel
        revision: Notifications.historyRevision
        filter: root.filter
    }

    property bool _clearing: false
    property int _timeTick: 0
    property real _nowMs: 0
    property real _todayStartMs: 0

    function _touchNow(): void {
        const nowMs = Date.now()
        const now = new Date(nowMs)
        root._nowMs = nowMs
        root._todayStartMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        root._timeTick++
    }

    Component.onCompleted: root._touchNow()

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._touchNow() }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active && MenuState.open && !Idle.isIdle
        onTriggered: root._touchNow()
    }

    onPageHidden: {
        _clearButton.disarm()
    }

    function formatTime(ms): string {
        const nowMs = root._nowMs > 0 ? root._nowMs : Date.now()
        const value = Number(ms || nowMs)
        const diff = Math.max(0, nowMs - value)
        if (diff < 60000)   return "now"
        if (diff < 3600000) return Math.floor(diff / 60000) + "m"

        const d = new Date(value)
        const today = root._todayStartMs > 0 ? root._todayStartMs : nowMs
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        // whole days, not milliseconds: a DST day is 23 or 25 hours long, and the raw
        // gap then lands one bucket early — two sections both headed Yesterday
        const days = Math.round((today - day) / 86400000)
        if (days <= 0 && diff < 86400000) return Math.floor(diff / 3600000) + "h"
        // the section header already carries the day, so an older entry only owes a clock
        // qt only counts 12-hour when AP shares the format string
        return Qt.formatDateTime(d, ShellSettings.clock12h ? "h:mm ap" : "HH:mm")
    }

    function dayKey(ms): string {
        const d = new Date(Number(ms || root._nowMs || Date.now()))
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function sectionLabel(ms): string {
        const nowMs = root._nowMs > 0 ? root._nowMs : Date.now()
        const value = Number(ms || nowMs)
        const d = new Date(value)
        const today = root._todayStartMs > 0 ? root._todayStartMs : nowMs
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const days = Math.round((today - day) / 86400000)
        if (days <= 0) return "Today"
        if (days === 1) return "Yesterday"
        if (days < 7) return Qt.formatDateTime(d, "dddd")
        return Qt.formatDateTime(d, "MMM d, yyyy")
    }


    function clearAll(): void {
        if (_clearing || root.rowCount === 0) return
        if (ShellSettings.reduceMotion) {
            Notifications.clearHistoryFor(root.filter)
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
                Notifications.clearHistoryFor(root.filter)
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
            height: Metrics.rowHeightFor(38)

            ShellText {
                id: _headerTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Math.min(implicitWidth,
                    (_clearButton.visible ? _clearButton.x - 10 : _header.width)
                    - (_countChip.visible ? _countChip.width + 9 : 0)))
                text: root.filter.length > 0 ? root.filter : "Notifications"
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
                visible: root.rowCount > 0
                width:  Math.max(18, _countTxt.implicitWidth + 12)
                height: 18
                radius: 9
                antialiasing: true
                color: Theme.withAlpha(Theme.subtext, 0.12)

                ShellText {
                    id: _countTxt
                    anchors.centerIn: parent
                    text: String(root.rowCount)
                    color: Theme.withAlpha(Theme.text, 0.62)
                    font.pixelSize: Settings.fontMicro
                    font.weight: Font.DemiBold
                }
            }

            ConfirmButton {
                id: _clearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.rowCount > 0
                glyph: "󰆴"
                label: "Clear"
                busy:  root._clearing
                onConfirmed: root.clearAll()
            }
        }

        Item {
            width: parent.width
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            visible: root.rowCount === 0

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
                        text: "󱇦"
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

                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "New notifications will appear here"
                    color: Theme.withAlpha(Theme.subtext,
                        ShellSettings.highContrast ? 0.72 : 0.52)
                    font.pixelSize: Settings.fontCaption
                }
            }
        }

        ShellListView {
            id: _historyList
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: parent.width
            // runs of one app close up and days pull apart, so every gap is carried by the delegate
            spacing: 0
            visible: root.rowCount > 0
            cacheBuffer: 240
            reuseItems: true
            model: _filtered.model

            // clearAll runs its own fade over the whole list, so per-row motion there
            // would animate every delegate at once behind an already-invisible list
            displaced: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Easing.OutCubic }
            }
            add: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fast }
            }
            remove: Transition {
                enabled: !root._clearing
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: Motion.fast; easing.type: Easing.InCubic }
                    NumberAnimation { property: "x"; to: 20; duration: Motion.fast; easing.type: Easing.InCubic }
                }
            }
            removeDisplaced: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                    id: _entry
                    // a ListModel delegate gets roles, not modelData; alias so the rest of the entry reads the same
                    required property var model
                    readonly property var modelData: model
                    required property int index

                    readonly property var _prev: index > 0
                        ? _filtered.model.get(index - 1) : null
                    readonly property bool _critical: Number(modelData.urgency) === 2
                    readonly property bool _showSection: !_prev
                        || root.dayKey(modelData.time) !== root.dayKey(_prev.time)
                    // a run of one app carries its name once; the rest of the run is just the messages
                    readonly property bool _showHeader: _showSection
                        || String(_prev.appName) !== String(modelData.appName)

                    readonly property string _appIconSource: {
                        Notifications.entriesTick
                        return _entry._showHeader ? Notifications.appIconSource(
                            modelData.appIcon, modelData.desktopEntry, modelData.appName) : ""
                    }
                    readonly property string _appIconFallback: {
                        Notifications.entriesTick
                        return _entry._showHeader ? Notifications.entryIconSource(
                            modelData.desktopEntry, modelData.appName) : ""
                    }

                    readonly property int _topPad: 11
                    readonly property int _sidePad: 14
                    readonly property int _rightGutter: _rightSlot.width + 10
                    readonly property int _firstLineHeight: _showHeader ? _metaRow.height : _summary.height
                    readonly property int _sectionHeight: _showSection ? 24 : 0
                    readonly property int _gapAbove: index === 0 ? 0
                        : _showSection ? 14 : _showHeader ? 8 : 3
                    readonly property int _cardHeight: Metrics.snap4Up(
                        _entryContent.implicitHeight + 2 * _entry._topPad)
                    readonly property int _fullHeight: _gapAbove + _sectionHeight + _cardHeight
                    property bool _removing: false
                    property bool _expanded: false

                    function _toggleExpand(): void {
                        if (_expanded) _expanded = false
                        else if (_body.truncated) _expanded = true
                    }

                    width: _historyList.width
                    height: _fullHeight
                    clip: true

                    // text lays out a frame after the delegate completes, so an ungated behaviour animates every row as it scrolls into view
                    property bool _heightReady: false
                    Timer { id: _heightArm; interval: 0; onTriggered: _entry._heightReady = true }
                    Component.onCompleted: _heightArm.start()
                    Component.onDestruction: _heightArm.stop()
                    ListView.onPooled: {
                        _heightArm.stop()
                        _entry._heightReady = false
                        _entry._expanded = false
                        _entry._removing = false
                    }
                    ListView.onReused: {
                        // the remove transition pools the row at its faded-out x and opacity
                        _entry.x = 0
                        _entry.opacity = 1
                        _entry._expanded = false
                        _entry._removing = false
                        _entry._heightReady = false
                        _heightArm.restart()
                    }
                    MotionBehavior on height {
                        gate: _entry._heightReady
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                    }

                    function removeSelf(): void {
                        if (_removing || root._clearing) return
                        const rowIndex = index
                        // persist immediately. A delegate-owned delay is lost if the user changes pages before its timer fires
                        _removing = true
                        Notifications.removeFromHistory(rowIndex)
                    }

                    Item {
                        visible: _entry._showSection
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        y: _entry._gapAbove
                        height: _entry._sectionHeight

                        ShellText {
                            id: _secText
                            anchors.left:           parent.left
                            anchors.leftMargin:     4
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root._timeTick; return root.sectionLabel(_entry.modelData.time) }
                            color: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.22), 0.74)
                            font.pixelSize: Settings.fontMicro
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
                        y: _entry._gapAbove + _entry._sectionHeight
                        width: parent.width
                        height: _entry._cardHeight
                        radius: Theme.radiusControl
                        antialiasing: true
                        color: Theme.rowFill(_entryHover.hovered, _entryTap.pressed)

                        OutlineBorder {
                            radius: _card.radius
                            outlineWidth: 1
                            outlineColor: _entry._critical ? Theme.withAlpha(Theme.error, 0.50)
                                : Theme.menuCardBorder
                            // same gate as the height above: a recycled row would otherwise
                            // cross-fade the previous notification's urgency colour into view
                            ColorFade on outlineColor { gate: _entry._heightReady }
                        }

                        ColorFade on color { gate: _entry._heightReady }

                        Accessible.role: Accessible.Notification
                        Accessible.name: String(_entry.modelData.appName || "").length > 0
                            ? _entry.modelData.appName + ": " + _summary.text : _summary.text
                        Accessible.description: _body.text
                        Accessible.focusable: true
                        Accessible.onPressAction: _entry._toggleExpand()

                        HoverHandler {
                            id: _entryHover
                            cursorShape: (_body.truncated || _entry._expanded) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            id: _entryTap
                            enabled: !root._clearing && !_entry._removing
                            onTapped: eventPoint => {
                                const p = _rightSlot.mapFromItem(_card, eventPoint.position.x, eventPoint.position.y)
                                if (_rightSlot.contains(p)) return
                                _entry._toggleExpand()
                            }
                        }

                        Column {
                            id: _entryContent
                            anchors.left: parent.left
                            anchors.leftMargin: _entry._sidePad
                            anchors.right: parent.right
                            anchors.rightMargin: _entry._sidePad
                            anchors.top: parent.top
                            anchors.topMargin: _entry._topPad
                            spacing: 3

                            Row {
                                id: _metaRow
                                width: parent.width
                                height: visible ? Math.max(16, _appName.implicitHeight) : 0
                                visible: _entry._showHeader
                                spacing: 7

                                Item {
                                    id: _appIconSlot
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16

                                    readonly property string _fallbackSource: String(
                                        _entry.modelData.appName || _entry.modelData.summary || "N").trim()

                                    ShellText {
                                        anchors.centerIn: parent
                                        visible: _recentAppIcon.status !== Image.Ready
                                        text: SafeText.initial(_appIconSlot._fallbackSource, "N")
                                        color: Theme.withAlpha(Theme.subtext, 0.70)
                                        font.pixelSize: Settings.fontMicro
                                        font.weight: Font.DemiBold
                                    }

                                    IconImage {
                                        id: _recentAppIcon
                                        anchors.fill: parent
                                        visible: status === Image.Ready
                                        // without this the themed icon decodes at its native size (often 256px+) to paint 16px
                                        implicitSize: 16
                                        // a deleted temp icon is still a valid path, so only the load failing reveals it
                                        property bool _fellBack: false
                                        readonly property string _primary: _entry._appIconSource
                                        on_PrimaryChanged: _fellBack = false
                                        source: _fellBack ? _entry._appIconFallback : _primary
                                        onStatusChanged: if (status === Image.Error
                                                && _entry._appIconFallback.length > 0
                                                && _entry._appIconFallback !== _primary)
                                            _fellBack = true
                                        asynchronous: true
                                    }
                                }

                                ShellText {
                                    id: _appName
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - _appIconSlot.width
                                        - parent.spacing - _entry._rightGutter)
                                    text: _entry.modelData.appName || "Notification"
                                    color: _entry._critical ? Theme.error : Theme.withAlpha(Theme.subtext, 0.70)
                                    font.pixelSize: Settings.fontCaption
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            ShellText {
                                id: _summary
                                width: Math.max(0, parent.width
                                    - (_metaRow.visible ? 0 : _entry._rightGutter))
                                text: _entry.modelData.summary || "Notification"
                                color: Theme.text
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            ShellText {
                                id: _body
                                width: parent.width
                                rightPadding: 16
                                visible: text.length > 0
                                text: _entry.modelData.body || ""
                                color: Theme.withAlpha(Theme.text, 0.58)
                                font.pixelSize: Settings.fontLabel
                                wrapMode: Text.Wrap
                                maximumLineCount: _entry._expanded ? 12 : 2
                                elide: Text.ElideRight
                            }
                        }

                        // one right column for both states: the timestamp rests there and the
                        // remove button takes its place under the pointer, so nothing reflows on hover
                        Item {
                            id: _rightSlot
                            anchors.right: parent.right
                            anchors.rightMargin: _entry._sidePad
                            anchors.top: parent.top
                            anchors.topMargin: _entry._topPad
                                + Math.round((_entry._firstLineHeight - height) / 2)
                            width: Math.max(24, _entryTime.implicitWidth)
                            height: 24
                            z: 2

                            ShellText {
                                id: _entryTime
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: { root._timeTick; return root.formatTime(_entry.modelData.time) }
                                color: Theme.withAlpha(Theme.subtext, 0.42)
                                font.pixelSize: Settings.fontMicro
                                opacity: _entryHover.hovered ? 0 : 1
                                MotionBehavior on opacity { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast } }
                            }

                            Rectangle {
                                id: _removeButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 12
                                antialiasing: true

                                color: _removeTap.pressed
                                    ? Theme.withAlpha(Theme.error, 0.24)
                                    : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.17) : Theme.withAlpha(Theme.subtext, 0.08)
                                opacity: _entryHover.hovered ? 1.0 : 0.0
                                visible: opacity > 0.001
                                scale: _removeTap.pressed ? 0.94 : 1.0

                                ColorFade on color { gate: _entry._heightReady }
                                MotionBehavior on opacity { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast } }

                                OutlineBorder {
                                    radius: _removeButton.radius
                                    outlineWidth: 1
                                    outlineColor: _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.36) : Theme.menuControlLine
                                    ColorFade on outlineColor { gate: _entry._heightReady }
                                }
                                MotionBehavior on scale { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove notification"
                                Accessible.focusable: true
                                Accessible.onPressAction: _entry.removeSelf()

                                HoverHandler { id: _removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { id: _removeTap; enabled: !root._clearing && !_entry._removing; onTapped: _entry.removeSelf() }

                                ShellText {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: _removeHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.56)
                                    font.pixelSize: Settings.fontCaption
                                }
                            }
                        }

                        ShellText {
                            anchors.right: parent.right
                            anchors.rightMargin: _entry._sidePad - 2
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: _entry._topPad - 4
                            visible: _entry._expanded || _body.truncated
                            text: "󰅀"
                            color: Theme.withAlpha(Theme.subtext,
                                _entryHover.hovered ? 0.80 : 0.38)
                            font.pixelSize: Settings.fontMicro
                            rotation: _entry._expanded ? 180 : 0
                            transformOrigin: Item.Center
                            ColorFade on color { gate: _entry._heightReady }
                            MotionBehavior on rotation { gate: _entry._heightReady; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
                        }
                    }
            }
        }

        ListEdgeLines {
            anchors.fill: _historyList
            visible: root.rowCount > 0
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
            shown: root.rowCount > 0
            z: 3
        }
    }
}
