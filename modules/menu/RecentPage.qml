import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    width: parent ? parent.width : 0
    implicitHeight: _histCol.implicitHeight
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    transformOrigin: Item.Center

    property bool _entering: false
    layer.enabled: _entering && !ShellSettings.reduceMotion

    Component.onCompleted: opacity = root.active ? 1.0 : 0.0

    property int _timeTick: 0

    onActiveChanged: {
        if (root.active) {
            _timeTick++
            _exit.stop()
            if (root.opacity < 0.001) root.scale = 0.96
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
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(160); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale";   to: 1.0; duration: Motion.ms(210); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(110); easing.type: Easing.InCubic }
        ScriptAction { script: { root.scale = 1.0 } }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.active && MenuState.open
        onTriggered: root._timeTick++
    }

    // Single human-friendly timestamp, picks the form that fits the age
    function formatTime(ms): string {
        const diff = Date.now() - ms
        if (diff < 60000)     return "just now"
        if (diff < 3600000)   return Math.floor(diff / 60000)   + "m ago"
        if (diff < 86400000)  return Math.floor(diff / 3600000) + "h ago"
        if (diff < 172800000) return "Yesterday"
        const d = new Date(ms)
        if (diff < 604800000) return Qt.formatDateTime(d, "ddd")     // "Mon"
        return Qt.formatDateTime(d, "MMM dd")
    }

    // Clear-all plays as a top-to-bottom collapse cascade (each card peels away in
    // turn), then the model is emptied centrally once they've gone. reduce-motion
    // clears instantly.
    signal clearAllRequested()
    property bool _clearing: false
    function _clearAll(): void {
        if (_clearing) return
        if (ShellSettings.reduceMotion || Notifications.historyCount === 0) { Notifications.clearHistory(); return }
        _clearing = true
        clearAllRequested()
        _clearFinish.interval = Math.min(Notifications.historyCount - 1, 12) * 32 + Motion.fast + 90
        _clearFinish.restart()
    }
    Timer {
        id: _clearFinish
        onTriggered: { Notifications.clearHistory(); root._clearing = false }
    }

    Column {
        id: _histCol
        width: parent.width
        spacing: 0

        Item { width: 1; height: 14 }

        Item {
            width: parent.width; height: 30
            visible: Notifications.hasHistory
            Rectangle {
                id: _clearBtn
                anchors.right: parent.right; anchors.rightMargin: 0
                anchors.verticalCenter: parent.verticalCenter
                width: _clearRow.implicitWidth + 22; height: 26; radius: 13
                antialiasing: true
                // Press darkens fill/border instead of scaling (scaling blurs the
                // NativeRendering text inside).
                color: _clearPress.pressed
                    ? Theme.withAlpha(Theme.error, 0.24)
                    : _clearHover.hovered
                        ? Theme.withAlpha(Theme.error, 0.14)
                        : Theme.withAlpha(Theme.subtext, 0.08)
                border.width: 1
                border.color: _clearPress.pressed
                    ? Theme.withAlpha(Theme.error, 0.52)
                    : _clearHover.hovered
                        ? Theme.withAlpha(Theme.error, 0.30)
                        : Theme.withAlpha(Theme.subtext, 0.14)
                Behavior on color        { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                HoverHandler { id: _clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler   { id: _clearPress; enabled: !root._clearing; onTapped: root._clearAll() }

                Row {
                    id: _clearRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰆴"
                        color: _clearHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.50)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear all"
                        color: _clearHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.55)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
            }
        }

        Item { width: 1; height: 8; visible: Notifications.hasHistory }

        Item {
            id: _histListWrap
            width:   parent.width
            height:  _histList.height
            visible: Notifications.hasHistory

            ListView {
                id: _histList
                width: parent.width
                height: Math.min(contentHeight, 300)
                clip: true
                boundsMovement: Flickable.StopAtBounds
                flickDeceleration: 1800
                maximumFlickVelocity: 2200
                spacing: 6
                model: Notifications.history

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.ms(200); easing.type: Easing.OutCubic }
                        NumberAnimation { property: "y"; from: -12; duration: Motion.ms(220); easing.type: Easing.OutCubic }
                    }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: Motion.ms(140); easing.type: Easing.InCubic }
                }
                removeDisplaced: Transition {
                    NumberAnimation { property: "y"; duration: Motion.ms(180); easing.type: Easing.OutCubic }
                }

            delegate: Rectangle {
                id: _card
                required property var modelData
                required property int index

                // Staggered reveal on tab open. Translate only, so NativeRendering
                // text stays crisp and it can't fight the ListView transitions.
                property real _reveal: 1
                transform: Translate { y: (1 - _card._reveal) * 14 }

                // Collapse + fade on delete/clear-all: a JS-array model reset plays
                // no remove transition, so peel the card first, then touch the model.
                property bool _removing: false
                readonly property int _fullH: _entryCol.implicitHeight + 26
                property var _pendingRemove: null
                function _deleteSelf(): void {
                    if (ShellSettings.reduceMotion) { Notifications.removeFromHistory(modelData); return }
                    _removing = true
                    _pendingRemove = _card.modelData
                    _delTimer.restart()
                }
                Timer {
                    id: _delTimer
                    interval: Motion.fast + 40
                    onTriggered: {
                        if (_card._pendingRemove !== null) {
                            Notifications.removeFromHistory(_card._pendingRemove)
                            _card._pendingRemove = null
                        }
                    }
                }
                Connections {
                    target: root
                    function onClearAllRequested() {
                        if (ShellSettings.reduceMotion) return
                        _clearStagger.interval = Math.min(_card.index, 12) * 32
                        _clearStagger.restart()
                    }
                }
                Timer { id: _clearStagger; onTriggered: _card._removing = true }

                width: _histList.width
                height: _removing ? 0 : _fullH
                opacity: _removing ? 0.0 : 1.0
                clip: true
                Behavior on height  { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.InCubic } }
                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                radius: 12; antialiasing: true
                color: Theme.rowFill(_entryHover.hovered, modelData.urgency === 2)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                border.width: 1
                // Quiet subtext edge: archived items shouldn't carry the popup's
                // live accent border.
                border.color: modelData.urgency === 2
                    ? Theme.withAlpha(Theme.error,   0.55)
                    : Theme.withAlpha(Theme.subtext, 0.16)

                HoverHandler { id: _entryHover }

                Connections {
                    target: root
                    enabled: !ShellSettings.reduceMotion
                    function onActiveChanged() {
                        if (root.active) { _card._reveal = 0; _cardReveal.restart() }
                    }
                }
                SequentialAnimation {
                    id: _cardReveal
                    PauseAnimation  { duration: Math.min(_card.index, 8) * 32 }
                    NumberAnimation { target: _card; property: "_reveal"; to: 1; duration: Motion.ms(300); easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.top:        parent.top
                    anchors.right:      parent.right
                    anchors.topMargin:  7
                    anchors.rightMargin: 7
                    width: 18; height: 18; radius: 9
                    antialiasing: true
                    color:        _xHover.hovered ? Theme.withAlpha(Theme.error, 0.18) : Theme.withAlpha(Theme.subtext, 0.10)
                    border.width: 1
                    border.color: _xHover.hovered ? Theme.withAlpha(Theme.error, 0.32) : Theme.withAlpha(Theme.subtext, 0.14)
                    opacity: _entryHover.hovered ? 1.0 : 0.0
                    scale:   _entryHover.hovered ? 1.0 : 0.6
                    transformOrigin: Item.Center
                    z: 2
                    Behavior on opacity      { NumberAnimation { duration: Motion.fast } }
                    Behavior on scale        { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                    Behavior on color        { ColorAnimation  { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation  { duration: Motion.fast } }
                    HoverHandler { id: _xHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { enabled: !root._clearing && !_card._removing; onTapped: _card._deleteSelf() }
                    Text {
                        anchors.centerIn: parent
                        text:  "󰅖"
                        color: _xHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.55)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize - 2
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }

                Column {
                    id: _entryCol
                    anchors {
                        left: parent.left;   leftMargin: 16
                        right: parent.right; rightMargin: 16
                        top: parent.top;     topMargin: 13
                    }
                    spacing: 5

                    // Summary, leads
                    Text {
                        // Reserve room for the hover-reveal delete button so a long
                        // summary never elides underneath it.
                        width: parent.width - 14
                        text: modelData.summary || ""
                        textFormat: Text.PlainText
                        color: modelData.urgency === 2 ? Theme.error : Theme.text
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    // Body
                    Text {
                        width: parent.width
                        text: modelData.body || ""
                        textFormat: Text.PlainText
                        visible: (modelData.body || "").length > 0
                        color: Theme.withAlpha(Theme.text, 0.62)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
                        renderType: Text.NativeRendering
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            id: _appCap
                            anchors.verticalCenter: parent.verticalCenter
                            visible: text.length > 0
                            text: modelData.appName || ""
                            textFormat: Text.PlainText
                            color: Theme.withAlpha(Theme.subtext, modelData.urgency === 2 ? 0.85 : 0.50)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 3
                            font.weight: Font.Medium
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.6
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, Math.max(0, parent.width - _capDot.implicitWidth - _timeLabel.implicitWidth - parent.spacing * 2))
                        }
                        Text {
                            id: _capDot
                            anchors.verticalCenter: parent.verticalCenter
                            visible: _appCap.visible
                            text: "·"
                            color: Theme.withAlpha(Theme.subtext, 0.32)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 3
                            renderType: Text.NativeRendering
                        }
                        Text {
                            id: _timeLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root._timeTick; return root.formatTime(modelData.time) }
                            color: Theme.withAlpha(Theme.subtext, 0.38)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 3
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
            }

            ListEdgeFade {
                anchors.fill: parent
                z: 1
                list: _histList
            }
        }

        Item { width: 1; height: 10 }
    }
}
