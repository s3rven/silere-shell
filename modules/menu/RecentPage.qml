pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    required property bool active
    required property bool powerOpen
    required property int viewportHeight

    width: parent ? parent.width : 0
    implicitHeight: viewportHeight
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    transformOrigin: Item.Center

    property bool _entering: false
    property bool _clearing: false
    property int _timeTick: 0

    layer.enabled: _entering && !ShellSettings.reduceMotion

    Component.onCompleted: opacity = root.active ? 1.0 : 0.0

    onActiveChanged: {
        if (root.active) {
            _timeTick++
            _exit.stop()
            if (root.opacity < 0.001) root.scale = 0.97
            _enter.restart()
        } else {
            _enter.stop()
            _exit.restart()
        }
    }

    ParallelAnimation {
        id: _enter
        onStarted: root._entering = true
        onStopped: root._entering = false
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(140); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1.0; duration: Motion.ms(180); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(100); easing.type: Easing.InCubic }
        ScriptAction { script: root.scale = 1.0 }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active && MenuState.open && !Idle.isIdle
        onTriggered: root._timeTick++
    }

    function formatTime(ms): string {
        const diff = Math.max(0, Date.now() - Number(ms || Date.now()))
        if (diff < 60000)     return "just now"
        if (diff < 3600000)   return Math.floor(diff / 60000) + "m"
        if (diff < 86400000)  return Math.floor(diff / 3600000) + "h"
        if (diff < 172800000) return "Yesterday"
        if (diff < 604800000) return Qt.formatDateTime(new Date(ms), "ddd")
        return Qt.formatDateTime(new Date(ms), "MMM d")
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

    function clearAll(): void {
        if (_clearing || Notifications.historyCount === 0) return
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

            Text {
                id: _headerTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.text
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
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

                Text {
                    id: _countTxt
                    anchors.centerIn: parent
                    text: String(Notifications.historyCount)
                    color: Theme.withAlpha(Theme.text, 0.62)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize - 3
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }
            }

            Rectangle {
                id: _clearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifications.hasHistory
                width: visible ? 68 : 0
                height: 30
                radius: Theme.radiusControl
                antialiasing: true
                activeFocusOnTab: visible

                color: _clearTap.pressed
                    ? Theme.withAlpha(Theme.error, 0.20)
                    : _clearHover.hovered ? Theme.withAlpha(Theme.subtext, 0.16) : Theme.menuControl
                border.width: activeFocus ? 2 : 1
                border.color: activeFocus
                    ? Theme.withAlpha(Theme.error, 0.88)
                    : _clearHover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
                opacity: root._clearing ? 0.45 : 1.0

                Accessible.role: Accessible.Button
                Accessible.name: "Clear all notifications"
                Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.clearAll(); event.accepted = true }
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.clearAll(); event.accepted = true }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.clearAll(); event.accepted = true }

                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                HoverHandler { id: _clearHover; enabled: !root._clearing; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { id: _clearTap; enabled: !root._clearing; onTapped: root.clearAll() }

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰆴"
                        color: _clearHover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.72)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear"
                        color: _clearHover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.text, 0.76)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 2
                        renderType: Text.NativeRendering
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
                    border.width: 1
                    border.color: Theme.menuCardBorder

                    Text {
                        anchors.centerIn: parent
                        text: "󰂛"
                        color: Theme.withAlpha(Theme.subtext, 0.34)
                        font.family: Settings.font
                        font.pixelSize: 24
                        renderType: Text.NativeRendering
                    }
                }

                Item { width: 1; height: 2 }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "All caught up"
                    color: Theme.withAlpha(Theme.text, 0.78)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize + 1
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Dismissed notifications will appear here"
                    color: Theme.withAlpha(Theme.subtext, 0.42)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize - 2
                    renderType: Text.NativeRendering
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
            model: Notifications.history

            delegate: Item {
                    id: _entry
                    required property var modelData
                    required property int index

                    readonly property bool _critical: Number(modelData.urgency) === 2
                    readonly property bool _showSection: index === 0
                        || root.dayKey(modelData.time) !== root.dayKey(Notifications.history[index - 1]?.time)
                    readonly property int _sectionHeight: _showSection ? 26 : 0
                    readonly property int _cardHeight: Math.max(70, _entryContent.implicitHeight + 20)
                    readonly property int _fullHeight: _sectionHeight + _cardHeight
                    property bool _removing: false
                    property var _pendingRemove: null

                    width: _historyList.width
                    height: _removing ? 0 : _fullHeight
                    opacity: _removing ? 0 : 1
                    clip: true

                    Behavior on height {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.InCubic }
                    }
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.fast }
                    }

                    function removeSelf(): void {
                        if (_removing || root._clearing) return
                        if (ShellSettings.reduceMotion) {
                            Notifications.removeFromHistory(modelData)
                            return
                        }
                        _pendingRemove = modelData
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

                    // Day divider — mirrors the Now page's SectionLabel so both
                    // tabs read as one app: accent tick, accent-leaning label, rule.
                    Item {
                        visible: _entry._showSection
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        height: _entry._sectionHeight

                        Rectangle {
                            id: _secTick
                            anchors.left:           parent.left
                            anchors.leftMargin:     2
                            anchors.verticalCenter: _secText.verticalCenter
                            width:  3
                            height: Math.round(_secText.implicitHeight * 0.82)
                            radius: 1.5
                            antialiasing: true
                            color:  Theme.withAlpha(Theme.accent, 0.75)
                        }

                        Text {
                            id: _secText
                            anchors.left:           _secTick.right
                            anchors.leftMargin:     7
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root._timeTick; return root.sectionLabel(_entry.modelData.time) }
                            color: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.22), 0.74)
                            font.family: Settings.font
                            font.pixelSize: Settings.fontSize - 3
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.4
                            renderType: Text.NativeRendering
                        }

                        Rectangle {
                            anchors.left:           _secText.right
                            anchors.leftMargin:     10
                            anchors.right:          parent.right
                            anchors.verticalCenter: _secText.verticalCenter
                            height: 1
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
                        border.width: 1
                        border.color: _entry._critical
                            ? Theme.withAlpha(Theme.error, 0.50)
                            : Theme.menuCardBorder

                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        HoverHandler { id: _entryHover }

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
                            anchors.leftMargin: 13
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 9
                            spacing: 3

                            Row {
                                width: parent.width
                                spacing: 7

                                Text {
                                    id: _appName
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - _entryTime.implicitWidth - parent.spacing - 24)
                                    text: _entry.modelData.appName || "Notification"
                                    textFormat: Text.PlainText
                                    color: _entry._critical ? Theme.error : Theme.withAlpha(Theme.subtext, 0.70)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize - 2
                                    font.weight: Font.Medium
                                    renderType: Text.NativeRendering
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: _entryTime
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: { root._timeTick; return root.formatTime(_entry.modelData.time) }
                                    color: Theme.withAlpha(Theme.subtext, 0.42)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize - 3
                                    renderType: Text.NativeRendering
                                }
                            }

                            Text {
                                width: parent.width
                                text: _entry.modelData.summary || "Notification"
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: _entry.modelData.body || ""
                                textFormat: Text.PlainText
                                color: Theme.withAlpha(Theme.text, 0.58)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 1
                                renderType: Text.NativeRendering
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: _removeButton
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            width: 20
                            height: 20
                            radius: 10
                            antialiasing: true
                            activeFocusOnTab: true
                            z: 2

                            color: _removeTap.pressed
                                ? Theme.withAlpha(Theme.error, 0.24)
                                : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.17) : Theme.withAlpha(Theme.subtext, 0.08)
                            border.width: activeFocus ? 2 : 1
                            border.color: activeFocus
                                ? Theme.withAlpha(Theme.error, 0.88)
                                : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.36) : Theme.menuControlLine
                            opacity: _entryHover.hovered || activeFocus ? 1.0 : 0.46
                            scale: _entryHover.hovered || activeFocus ? 1.0 : 0.88

                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + String(_entry.modelData.summary || "notification")
                            Keys.onSpacePressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }
                            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }
                            Keys.onEnterPressed: event => { if (!event.isAutoRepeat) _entry.removeSelf(); event.accepted = true }

                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                            HoverHandler { id: _removeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: _removeTap; enabled: !root._clearing && !_entry._removing; onTapped: _entry.removeSelf() }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: _removeHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.56)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType: Text.NativeRendering
                            }
                        }
                    }
            }
        }

        ListEdgeFade {
            anchors.fill: _historyList
            visible: Notifications.hasHistory
            z: 2
            list: _historyList
            fadeColor: Theme.menuPane
            thickness: 10
            maxOpacity: 0.42
        }
    }
}
