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
    property var _previewLeft: []
    property var _previewRight: []
    readonly property var _leftKeys: _draggingKey.length > 0
        ? _previewLeft : ShellSettings.barWidgetOrderLeftKeys
    readonly property var _rightKeys: _draggingKey.length > 0
        ? _previewRight : ShellSettings.barWidgetOrderRightKeys
    readonly property int _leftCount:  _leftKeys.length
    readonly property int _rightCount: _rightKeys.length
    readonly property bool _leftEmpty:  _leftCount === 0
    readonly property bool _rightEmpty: _rightCount === 0
    readonly property int  _leftPad:  _leftEmpty  ? _rowH : 0
    readonly property int  _rightPad: _rightEmpty ? _rowH : 0
    readonly property int  _listTop: 12 + _headerH
    readonly property real _leftBottom: _listTop + _leftCount * _rowH + _leftPad

    property string _expandedKey: ""
    readonly property int _expandedSlot: _combinedSlotOf(_expandedKey)
    readonly property int _expandedExtra: _expandedKey ? _optionsHeightFor(_expandedKey) : 0

    width:  parent ? parent.width : 0
    height: _leftBottom + _headerH + _rightCount * _rowH + _rightPad + _footerH + _expandedExtra
    implicitHeight: height
    Behavior on height { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    property string _draggingKey: ""
    property real   _dragY: 0
    property string _focusedKey: ""
    readonly property string _dragZone: _draggingKey.length > 0 ? _zoneForY(_dragY) : ""
    // the dragged key's preview slot
    readonly property int _dragSlot: _combinedSlotOf(_draggingKey)

    function _locate(key: string): var {
        const li = root._leftKeys.indexOf(key)
        if (li >= 0) return { zone: "left", index: li }
        const ri = root._rightKeys.indexOf(key)
        return ri >= 0 ? { zone: "right", index: ri } : { zone: "", index: -1 }
    }

    function _combinedSlotOf(key: string): int {
        if (!key) return -1
        const loc = root._locate(key)
        if (loc.index < 0) return -1
        return loc.zone === "left" ? loc.index : root._leftCount + loc.index
    }

    function _beginDrag(key: string): void {
        root._previewLeft = ShellSettings.barWidgetOrderLeftKeys.slice()
        root._previewRight = ShellSettings.barWidgetOrderRightKeys.slice()
        root._draggingKey = key
    }

    function _previewMove(key: string, zone: string, atIndex: int): void {
        const left = root._previewLeft.filter(k => k !== key)
        const right = root._previewRight.filter(k => k !== key)
        const target = zone === "left" ? left : right
        const clamped = Math.max(0, Math.min(target.length, Math.round(atIndex)))
        target.splice(clamped, 0, key)
        root._previewLeft = left
        root._previewRight = right
    }

    function _finishDrag(key: string): void {
        if (root._draggingKey !== key) return
        const loc = root._locate(key)
        if (loc.index >= 0)
            ShellSettings.setBarWidgetZone(key, loc.zone, loc.index)
        root._draggingKey = ""
        root._previewLeft = []
        root._previewRight = []
    }

    function _hasOptions(key: string): bool {
        return key === "battery" || key === "network" || key === "clock" || key === "media"
    }

    // static per key — a live read here becomes a model dependency that rebuilds every delegate on change
    function _optionsFor(key: string): var {
        if (key === "battery") return [
            { glyph: "󰂃", label: "Hide when charging or full", setting: "batteryAutoHide" }
        ]
        if (key === "clock") return [
            { glyph: "󱑂", label: "Seconds", setting: "showSeconds" },
            { glyph: "󰃭", label: "Date",    setting: "clockShowDate" },
            { glyph: "󰔟", label: "12-hour", setting: "clock12h" }
        ]
        if (key === "media") return [
            { glyph: "󰐊", label: "Playback helper", setting: "mediaWidgetHelper" }
        ]
        if (key === "network") return [
            { glyph: "󰓅", label: "Network speed", setting: "networkTrafficStats" },
            { glyph: "󰐃", label: "Always show speed", setting: "networkSpeedInline", nested: true, showWhen: "networkTrafficStats" },
            { glyph: "󰦝", label: "Show connection under VPN", setting: "netVpnShowLink" }
        ]
        return []
    }
    function _optionsAvailable(key: string): bool {
        if (key === "battery") return ShellSettings.barShowBattery && Battery.available
        if (key === "clock")   return ShellSettings.barShowClock
        if (key === "media")   return ShellSettings.barShowMedia
        if (key === "network") return ShellSettings.barShowNetwork && Network.toolAvailable
        return false
    }
    function _optionsNote(key: string): string {
        if (key === "battery") return Battery.available ? "Battery hidden" : "No battery"
        if (key === "clock")   return "Clock hidden"
        if (key === "media")   return "Media hidden"
        if (key === "network") return Network.toolAvailable ? "Network hidden" : "NetworkManager missing"
        return ""
    }
    function _optionsHeightFor(key: string): int {
        const rows = _optionsFor(key)
        let n = 0
        for (const r of rows)
            if (!r.showWhen || ShellSettings[r.showWhen]) n++
        return n > 0 ? n * root._optRowH + 8 : 0
    }

    function _yForSlot(slot: real): real {
        let y = slot < root._leftCount
            ? root._listTop + slot * root._rowH
            : root._leftBottom + root._headerH + (slot - root._leftCount) * root._rowH
        if (root._expandedSlot >= 0 && slot > root._expandedSlot)
            y += root._expandedExtra
        return y
    }
    function _zoneForY(y: real): string {
        return y < root._leftBottom - root._rowH / 2 ? "left" : "right"
    }
    function _slotForY(y: real): int {
        if (y < root._leftBottom - root._rowH / 2)
            return root._leftEmpty ? 0 : Math.max(0, Math.round((y - root._listTop) / root._rowH))
        const rightSlot = Math.round((y - root._yForSlot(root._leftCount)) / root._rowH)
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

    // landing-slot marker; parks on _dragY while hidden so appearing can't animate in from the top
    Rectangle {
        visible: root._dragSlot >= 0
        x: 2; width: root.width - 4
        y: visible ? root._yForSlot(root._dragSlot) + 2 : root._dragY + 2
        height: root._rowH - 4
        radius: 8
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.30)
        Behavior on y {
            // unqualified `visible` in a Behavior resolves to the document root, never this rectangle
            enabled: root._draggingKey.length > 0 && !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    // outline riding on the dragged row
    Rectangle {
        visible: root._draggingKey.length > 0
        x: 2; width: root.width - 4
        y: root._dragY + 2
        height: root._rowH - 4
        z: 30
        radius: 8
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.35)
    }

    Repeater {
        model: root._allKeys

        delegate: Item {
            id: _row
            required property string modelData
            readonly property string key:  modelData
            readonly property var    meta: ShellSettings.barWidgetMeta[key]
            readonly property var    _loc: root._locate(key)
            readonly property string zone: _loc.zone
            readonly property int _zoneIdx: _loc.index
            readonly property int _combinedSlot: zone === "left" ? _zoneIdx : root._leftCount + _zoneIdx
            readonly property bool _dragging: root._draggingKey === key
            readonly property bool _hasToggle: meta.setting.length > 0
            readonly property bool _checked: _hasToggle ? ShellSettings[meta.setting] : true
            readonly property bool _hasOptions: root._hasOptions(key)
            readonly property bool _expanded: root._expandedKey === key
            property bool _optionsLoaded: false
            on_ExpandedChanged: if (_expanded) _optionsLoaded = true

            x: 0
            width:  root.width
            height: root._rowH + (_expanded ? root._expandedExtra : 0)
            z: _dragging ? 20 : 1
            y: _dragging ? root._dragY : root._yForSlot(_combinedSlot)
            Behavior on y {
                enabled: root._draggingKey.length > 0 && !_row._dragging && !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }

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

                HoverHandler { id: _rowHover; cursorShape: _dragH.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                DragHandler {
                    id: _dragH
                    target: null
                    // captured once: translation is cumulative from press, so re-deriving the base each swap would snowball the row
                    property real _startY: 0
                    onActiveChanged: {
                        if (active) {
                            root._expandedKey = ""
                            _dragH._startY = root._yForSlot(_row._combinedSlot)
                            // dragY must be current before visibility flips or the marker/outline show at the stale spot
                            root._dragY = _dragH._startY
                            root._beginDrag(_row.key)
                        } else {
                            root._finishDrag(_row.key)
                        }
                    }
                    onTranslationChanged: {
                        if (!active) return
                        const minY = root._listTop
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
                        root._previewMove(_row.key, targetZone, targetIdxInZone)
                    }
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
                    active: _row._hasOptions && _row._optionsLoaded
                    sourceComponent: Column {
                        width: _optWrap.width
                        Repeater {
                            model: root._optionsFor(_row.key)
                            delegate: Item {
                                id: _opt
                                required property var modelData
                                readonly property bool _on: ShellSettings[modelData.setting]
                                readonly property bool _avail: root._optionsAvailable(_row.key)
                                readonly property bool _shown: !modelData.showWhen || ShellSettings[modelData.showWhen]
                                readonly property bool _canToggle: _row._expanded && _shown && _avail
                                visible: _shown
                                width: _optWrap.width
                                height: root._optRowH

                                activeFocusOnTab: _canToggle
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: _opt.modelData.label
                                Accessible.checked: _opt._on
                                function _activate(): void {
                                    if (!_opt._avail) return
                                    _optToggle.armFlipAnimation()
                                    ShellSettings[_opt.modelData.setting] = !ShellSettings[_opt.modelData.setting]
                                }
                                Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }
                                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }
                                Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _opt._activate(); event.accepted = true }

                                HoverHandler { id: _optHover; cursorShape: _opt._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { enabled: _opt._avail; onTapped: _opt._activate() }

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
                                    visible: (_optHover.hovered || _opt.activeFocus) && _opt._avail
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
                                    color: Theme.withAlpha(Theme.subtext, _opt._avail ? 0.85 : 0.4)
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
                                    color: Theme.withAlpha(Theme.text, _opt._avail ? 0.9 : 0.45)
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
                                    visible: !_opt._avail && text.length > 0
                                    text: root._optionsNote(_row.key)
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
                                    enabled: _opt._avail
                                    opacity: _opt._avail ? 1 : 0.45
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
            y: (_isLeft ? root._listTop : root._yForSlot(root._leftCount)) + 3
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

        // inset matches RowDividers
        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
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
