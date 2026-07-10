pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    readonly property int _rowH: 44
    readonly property int _optRowH: 40
    readonly property int _headerH: 28
    readonly property int _footerH: 40
    readonly property var _allKeys: ShellSettings._allBarWidgetKeys
    readonly property int _leftCount:  ShellSettings.barWidgetOrderLeftKeys.length
    readonly property int _rightCount: ShellSettings.barWidgetOrderRightKeys.length
    readonly property bool _leftEmpty:  _leftCount === 0
    readonly property bool _rightEmpty: _rightCount === 0
    readonly property int  _leftPad:  _leftEmpty  ? _rowH : 0
    readonly property int  _rightPad: _rightEmpty ? _rowH : 0

    property string _expandedKey: ""
    readonly property int _expandedSlot: {
        if (!_expandedKey) return -1
        const loc = ShellSettings.barWidgetLocate(_expandedKey)
        return loc.zone === "left" ? loc.index : _leftCount + loc.index
    }
    readonly property int _expandedExtra: _expandedKey ? _optionsHeightFor(_expandedKey) : 0

    width:  parent ? parent.width : 0
    height: 12 + _headerH + _leftCount * _rowH + _leftPad + _headerH + _rightCount * _rowH + _rightPad + _footerH + _expandedExtra
    implicitHeight: height
    Behavior on height { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    property string _draggingKey: ""
    property real   _dragY: 0
    property string _focusedKey: ""
    readonly property string _dragZone: _draggingKey.length > 0 ? _zoneForY(_dragY) : ""
    // the dragged key's committed slot — reorders are live, so this is where it lands on release
    readonly property int _dragSlot: {
        if (_draggingKey.length === 0) return -1
        const loc = ShellSettings.barWidgetLocate(_draggingKey)
        return loc.zone === "left" ? loc.index : _leftCount + loc.index
    }

    function _hasOptions(key: string): bool {
        return key === "battery" || key === "network" || key === "clock" || key === "media"
    }

    function _optionsFor(key: string): var {
        if (key === "battery") return [
            { glyph: "󰂃", label: "Hide when charging or full", setting: "batteryAutoHide",
              available: ShellSettings.barShowBattery && Battery.available,
              note: !Battery.available ? "No battery" : "Battery hidden", nested: false }
        ]
        if (key === "clock") {
            const a = ShellSettings.barShowClock
            return [
                { glyph: "󱑂", label: "Seconds", setting: "showSeconds",   available: a, note: "Clock hidden", nested: false },
                { glyph: "󰃭", label: "Date",    setting: "clockShowDate", available: a, note: "Clock hidden", nested: false },
                { glyph: "󰔟", label: "12-hour", setting: "clock12h",      available: a, note: "Clock hidden", nested: false }
            ]
        }
        if (key === "media") return [
            { glyph: "󰐊", label: "Playback helper", setting: "mediaWidgetHelper",
              available: ShellSettings.barShowMedia, note: "Media hidden", nested: false }
        ]
        if (key === "network") {
            const a = ShellSettings.barShowNetwork && Network.toolAvailable
            const note = !Network.toolAvailable ? "NetworkManager missing" : "Network hidden"
            const rows = [ { glyph: "󰓅", label: "Network speed", setting: "networkTrafficStats", available: a, note: note, nested: false } ]
            if (ShellSettings.networkTrafficStats)
                rows.push({ glyph: "󰐃", label: "Always show speed", setting: "networkSpeedInline", available: a, note: note, nested: true })
            rows.push({ glyph: "󰦝", label: "Show connection under VPN", setting: "netVpnShowLink", available: a, note: note, nested: false })
            return rows
        }
        return []
    }
    function _optionsHeightFor(key: string): int {
        const n = _optionsFor(key).length
        return n > 0 ? n * root._optRowH + 8 : 0
    }

    function _yForSlot(slot: real): real {
        let y = slot < root._leftCount
            ? 12 + root._headerH + slot * root._rowH
            : 12 + root._headerH + root._leftCount * root._rowH + root._leftPad + root._headerH + (slot - root._leftCount) * root._rowH
        if (root._expandedSlot >= 0 && slot > root._expandedSlot)
            y += root._expandedExtra
        return y
    }
    function _zoneForY(y: real): string {
        const leftBottom = 12 + root._headerH + root._leftCount * root._rowH + root._leftPad
        return y < leftBottom - root._rowH / 2 ? "left" : "right"
    }
    function _slotForY(y: real): int {
        const leftBottom = 12 + root._headerH + root._leftCount * root._rowH + root._leftPad
        const boundary = leftBottom - root._rowH / 2
        if (y < boundary)
            return root._leftEmpty ? 0 : Math.max(0, Math.round((y - 12 - root._headerH) / root._rowH))
        const rightRaw = y - root._yForSlot(root._leftCount)
        const rightSlot = Math.round(rightRaw / root._rowH)
        return root._leftCount + Math.max(0, Math.min(root._rightCount, rightSlot))
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        antialiasing: true
        color: Theme.menuCard
        border.width: 1
        border.color: Theme.menuCardBorder
    }

    Text {
        y: 20
        anchors.left: parent.left; anchors.leftMargin: 14
        text: "LEFT"
        color: root._dragZone === "left" ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.5)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Text {
        y: root._yForSlot(root._leftCount) - root._headerH + 8
        anchors.left: parent.left; anchors.leftMargin: 14
        text: "RIGHT"
        color: root._dragZone === "right" ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.5)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on y { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }

    // landing-slot marker: reorders commit live, so the vacated gap under the lifted row is the drop spot
    Rectangle {
        opacity: root._dragSlot >= 0 ? 1 : 0
        visible: opacity > 0.01
        x: 2; width: root.width - 4
        y: root._yForSlot(root._dragSlot) + 2
        height: root._rowH - 4
        radius: 8
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.30)
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on y { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }

    Repeater {
        model: root._allKeys

        delegate: Item {
            id: _row
            required property string modelData
            readonly property string key:  modelData
            readonly property var    meta: ShellSettings.barWidgetMeta[key]
            readonly property var    _loc: ShellSettings.barWidgetLocate(key)
            readonly property string zone: _loc.zone
            readonly property int _zoneIdx: _loc.index
            readonly property int _combinedSlot: zone === "left" ? _zoneIdx : root._leftCount + _zoneIdx
            readonly property bool _dragging: root._draggingKey === key
            readonly property bool _hasToggle: meta.setting.length > 0
            readonly property bool _checked: _hasToggle ? ShellSettings[meta.setting] : true
            readonly property bool _hasOptions: root._hasOptions(key)
            readonly property bool _expanded: root._expandedKey === key

            x: 0
            width:  root.width
            height: root._rowH + (_expanded ? root._expandedExtra : 0)
            // stay above siblings while animating home, or the released row dives under them mid-settle
            property bool _settling: false
            on_DraggingChanged: {
                if (_dragging) { _settling = false; _settleReset.stop() }
                else           { _settling = true;  _settleReset.restart() }
            }
            Timer { id: _settleReset; interval: Motion.fast + 60; onTriggered: _row._settling = false }
            z: _dragging ? 20 : (_settling ? 15 : 1)
            y: _dragging ? root._dragY : root._yForSlot(_combinedSlot)
            Behavior on y { enabled: !_row._dragging && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            scale: _dragging ? 1.02 : 1.0
            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }

            Item {
                id: _header
                width: parent.width
                height: root._rowH

                RowHoverBg {
                    anchors.fill: parent
                    cardInset:    2
                    topRadius:    10
                    bottomRadius: 10
                    active:       _row._dragging || _rowHover.hovered || _keyFocus.activeFocus
                    focusActive:  _keyFocus.activeFocus
                    fillColor:    _row._dragging ? Theme.accent : Theme.text
                    fillOpacity:  _row._dragging ? 0.10 : (_keyFocus.activeFocus ? 0.08 : 0.05)
                }

                HoverHandler { id: _rowHover; cursorShape: Qt.OpenHandCursor }
                DragHandler {
                    id: _dragH
                    target: null
                    // captured once: translation is cumulative from press, so re-deriving the base each swap would snowball the row
                    property real _startY: 0
                    onActiveChanged: {
                        if (active) {
                            root._expandedKey = ""
                            _dragH._startY = root._yForSlot(_row._combinedSlot)
                            root._draggingKey = _row.key
                            root._dragY = _dragH._startY
                        } else {
                            root._draggingKey = ""
                        }
                    }
                    onTranslationChanged: {
                        if (!active) return
                        const minY = 12 + root._headerH
                        const maxY = root._rightEmpty
                            ? root._yForSlot(root._leftCount)
                            : root._yForSlot(root._allKeys.length - 1)
                        root._dragY = Math.max(minY, Math.min(maxY, _dragH._startY + translation.y))
                        const targetSlot = root._slotForY(root._dragY)
                        // derive the zone from the drop position, not the combined slot — an empty left zone has no slot index to encode "left"
                        const targetZone = root._zoneForY(root._dragY)
                        const targetIdxInZone = targetZone === "left"
                            ? (root._leftEmpty ? 0 : targetSlot)
                            : targetSlot - root._leftCount
                        if (targetZone === _row.zone && targetIdxInZone === _row._zoneIdx) return
                        ShellSettings.setBarWidgetZone(_row.key, targetZone, targetIdxInZone)
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 8
                    antialiasing: true
                    color: "transparent"
                    opacity: _row._dragging ? 1 : 0
                    visible: opacity > 0.01
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent, 0.35)
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Item {
                    id: _handle
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 32

                    Text {
                        anchors.centerIn: parent
                        text: "⣿"
                        color: _row._dragging ? Theme.accent : Theme.withAlpha(Theme.subtext, _rowHover.hovered ? 0.75 : 0.45)
                        font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    HoverHandler { id: _handleHover; cursorShape: Qt.OpenHandCursor }
                }

                Text {
                    id: _glyph
                    anchors.left: _handle.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: _row.meta.glyph
                    color: _row._checked ? Theme.withAlpha(Theme.accent, 0.9) : Theme.withAlpha(Theme.subtext, 0.85)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize + 1
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.left: _glyph.right
                    anchors.leftMargin: 8
                    anchors.right: _chevron.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: _row.meta.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    // hidden widgets read clearly dimmer — scanning for what's off is this list's main job
                    color: _row._checked ? Theme.text : Theme.withAlpha(Theme.text, 0.55)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                }

                Item {
                    id: _chevron
                    width: 22
                    height: parent.height
                    anchors.right: _row._hasToggle ? _toggle.left : parent.right
                    anchors.rightMargin: _row._hasToggle ? 4 : 12

                    Text {
                        anchors.centerIn: parent
                        visible: _row._hasOptions
                        text: "󰅀"
                        rotation: _row._expanded ? 0 : -90
                        color: Theme.withAlpha(Theme.subtext, _chevHover.hovered || _row._expanded ? 0.85 : 0.5)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 1
                        renderType: Text.NativeRendering
                        Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    HoverHandler { id: _chevHover; enabled: _row._hasOptions; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: _row._hasOptions
                        onTapped: root._expandedKey = _row._expanded ? "" : _row.key
                    }
                }

                ToggleSwitch {
                    id: _toggle
                    visible: _row._hasToggle
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    checked: _row._checked

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            _toggle.armFlipAnimation()
                            ShellSettings[_row.meta.setting] = !ShellSettings[_row.meta.setting]
                        }
                    }
                }
            }

            Item {
                id: _optWrap
                y: root._rowH
                width: parent.width
                clip: true
                height: _row._expanded ? root._expandedExtra : 0
                opacity: _row._expanded ? 1 : 0
                visible: height > 0.5
                Behavior on height  { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }

                Rectangle {
                    x: 26; y: 2
                    width: 1
                    height: parent.height - 6
                    color: Theme.withAlpha(Theme.accent, 0.25)
                }

                Loader {
                    width: parent.width
                    active: _row._hasOptions
                    sourceComponent: Column {
                        width: _optWrap.width
                        Repeater {
                            model: root._optionsFor(_row.key)
                            delegate: Item {
                                id: _opt
                                required property var modelData
                                readonly property bool _on: ShellSettings[modelData.setting]
                                readonly property bool _canToggle: _row._expanded && modelData.available
                                width: _optWrap.width
                                height: root._optRowH

                                activeFocusOnTab: _canToggle
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: _opt.modelData.label
                                Accessible.checked: _opt._on
                                function _activate(): void {
                                    if (!_opt.modelData.available) return
                                    _optToggle.armFlipAnimation()
                                    ShellSettings[_opt.modelData.setting] = !ShellSettings[_opt.modelData.setting]
                                }
                                Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }
                                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }
                                Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }

                                HoverHandler { id: _optHover; cursorShape: _opt._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { enabled: _opt.modelData.available; onTapped: _opt._activate() }

                                // collapsing hides this subtree; hand keyboard focus back to the row instead of orphaning it
                                Connections {
                                    target: _row
                                    function on_ExpandedChanged() {
                                        if (!_row._expanded && _opt.activeFocus) _keyFocus.forceActiveFocus()
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 40
                                    anchors.rightMargin: 8
                                    anchors.topMargin: 2
                                    anchors.bottomMargin: 2
                                    radius: 8
                                    antialiasing: true
                                    visible: (_optHover.hovered || _opt.activeFocus) && _opt.modelData.available
                                    color: Theme.withAlpha(Theme.text, _opt.activeFocus ? 0.08 : 0.05)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.accent, _opt.activeFocus ? 0.45 : 0)
                                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    id: _optGlyph
                                    anchors.left: parent.left
                                    anchors.leftMargin: _opt.modelData.nested ? 58 : 44
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text: _opt.modelData.glyph
                                    color: Theme.withAlpha(Theme.subtext, _opt.modelData.available ? 0.85 : 0.4)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize - 1
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    id: _optLabel
                                    anchors.left: _optGlyph.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _opt.modelData.label
                                    textFormat: Text.PlainText
                                    color: _opt.modelData.available ? Theme.withAlpha(Theme.text, 0.9) : Theme.withAlpha(Theme.text, 0.45)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize - 1
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    anchors.left: _optLabel.right
                                    anchors.leftMargin: 8
                                    anchors.right: _optToggle.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !_opt.modelData.available && _opt.modelData.note.length > 0
                                    text: _opt.modelData.note
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                    color: Theme.withAlpha(Theme.subtext, 0.55)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize - 4
                                    renderType: Text.NativeRendering
                                }

                                ToggleSwitch {
                                    id: _optToggle
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: _opt.modelData.available
                                    opacity: _opt.modelData.available ? 1 : 0.45
                                    checked: _opt._on
                                }
                            }
                        }
                    }
                }
            }

            FocusScope {
                id: _keyFocus
                height: root._rowH
                width: parent.width
                activeFocusOnTab: true
                Accessible.role: _row._hasToggle ? Accessible.CheckBox : Accessible.ListItem
                Accessible.name: _row.meta.label
                Accessible.checked: _row._checked
                Accessible.description: (_row.zone === "left" ? "Left" : "Right") + " side of bar. Left and Right arrows swap sides, Ctrl+Up and Down reorder."
                onActiveFocusChanged: {
                    if (activeFocus) root._focusedKey = _row.key
                    else if (root._focusedKey === _row.key) root._focusedKey = ""
                }
                function flipVisibility(event: var): void {
                    if (!event.isAutoRepeat && _row._hasToggle)
                        ShellSettings[_row.meta.setting] = !ShellSettings[_row.meta.setting]
                    event.accepted = _row._hasToggle
                }
                function moveToZone(zone: string, event: var): void {
                    if (_row.zone === zone) return
                    const end = zone === "left"
                        ? ShellSettings.barWidgetOrderLeftKeys.length
                        : ShellSettings.barWidgetOrderRightKeys.length
                    ShellSettings.setBarWidgetZone(_row.key, zone, end)
                    event.accepted = true
                }
                Keys.onSpacePressed:  event => _keyFocus.flipVisibility(event)
                Keys.onReturnPressed: event => _keyFocus.flipVisibility(event)
                Keys.onEnterPressed:  event => _keyFocus.flipVisibility(event)
                Keys.onLeftPressed:   event => _keyFocus.moveToZone("left", event)
                Keys.onRightPressed:  event => _keyFocus.moveToZone("right", event)
                Keys.onUpPressed:   event => { if (event.modifiers & Qt.ControlModifier) { ShellSettings.moveBarWidget(_row.key, -1); event.accepted = true } }
                Keys.onDownPressed: event => { if (event.modifiers & Qt.ControlModifier) { ShellSettings.moveBarWidget(_row.key, +1); event.accepted = true } }
                Keys.onPressed: event => {
                    if (_row._hasOptions && event.key === Qt.Key_O) {
                        root._expandedKey = _row._expanded ? "" : _row.key
                        event.accepted = true
                    }
                }
            }
        }
    }

    Repeater {
        model: 2
        delegate: Rectangle {
            required property int index
            readonly property bool _isLeft: index === 0
            readonly property bool dragging: root._draggingKey.length > 0
            visible: _isLeft ? root._leftEmpty : root._rightEmpty
            x: 10; width: root.width - 20
            y: (_isLeft ? 12 + root._headerH : root._yForSlot(root._leftCount)) + 3
            height: root._rowH - 6
            radius: 10
            antialiasing: true
            color: Theme.withAlpha(Theme.accent, dragging ? 0.08 : 0.035)
            border.width: 1
            border.color: Theme.withAlpha(Theme.accent, dragging ? 0.4 : 0.18)
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on y { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: "drag a widget here"
                color: Theme.withAlpha(Theme.subtext, 0.6)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 3
                renderType: Text.NativeRendering
            }
        }
    }

    Item {
        id: _footer
        y: root.height - root._footerH
        width: parent.width
        height: root._footerH

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.right: parent.right
            anchors.rightMargin: 1
            anchors.top: parent.top
            height: 1
            color: Theme.menuDivider
        }

        Text {
            anchors.left: parent.left; anchors.leftMargin: 14
            anchors.right: _resetBtn.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            // keyboard bindings surface only while a row holds focus
            text: root._focusedKey.length > 0
                ? "← → swap sides · ctrl+↑ ↓ reorder"
                : "drag rows to reorder or swap sides"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.52)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize - 3
            renderType: Text.NativeRendering
        }

        SettingsActionButton {
            id: _resetBtn
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: contentWidth
            height: 28
            glyph: "󰑐"
            label: "Reset"
            onTriggered: ShellSettings.resetBarWidgets()
        }
    }
}
