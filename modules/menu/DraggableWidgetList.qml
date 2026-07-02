pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// Standalone card (draws its own chrome, doesn't nest in a SettingsCard —
// its rows are absolutely positioned for the drag reflow, which breaks
// SettingsCard's column-order-based corner/divider auto-derivation).
// One Repeater over the FIXED canonical key list gives every widget a
// stable delegate identity that survives reorders and zone moves — a
// Repeater bound directly to the live order arrays would tear down and
// recreate delegates on every drag step, killing the gesture mid-drag.
Item {
    id: root

    readonly property int _rowH: 44
    readonly property int _headerH: 28
    readonly property int _footerH: 40
    readonly property var _allKeys: ShellSettings._allBarWidgetKeys
    readonly property int _leftCount:  ShellSettings.barWidgetOrderLeftKeys.length
    readonly property int _rightCount: ShellSettings.barWidgetOrderRightKeys.length

    width:  parent ? parent.width : 0
    height: 12 + _headerH + _leftCount * _rowH + _headerH + _rightCount * _rowH + _footerH
    implicitHeight: height

    property string _draggingKey: ""
    property real   _dragY: 0

    // Combined slot index (0-based, spans both zones back-to-back) <-> the
    // pixel Y a row sits at while NOT mid-drag (header height inserted once
    // the left zone's rows are exhausted).
    function _yForSlot(slot: real): real {
        return slot < root._leftCount
            ? 12 + root._headerH + slot * root._rowH
            : 12 + root._headerH + root._leftCount * root._rowH + root._headerH + (slot - root._leftCount) * root._rowH
    }
    function _slotForY(y: real): int {
        // Boundary = the vertical midpoint of the last left-zone row, backed
        // out of _yForSlot rather than re-deriving the left-block height by
        // hand. An empty left zone has no "last row" to sit below, so any y
        // unconditionally resolves into the right zone.
        const boundary = root._leftCount > 0
            ? root._yForSlot(root._leftCount - 1) + root._rowH / 2
            : -Infinity
        if (y < boundary)
            return Math.max(0, Math.round((y - 12 - root._headerH) / root._rowH))
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
        color: Theme.withAlpha(Theme.subtext, 0.5)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
    }

    Text {
        y: root._yForSlot(root._leftCount) - root._headerH + 8
        anchors.left: parent.left; anchors.leftMargin: 14
        text: "RIGHT"
        color: Theme.withAlpha(Theme.subtext, 0.5)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
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

            x: 0
            width:  root.width
            height: root._rowH
            z: _dragging ? 20 : 1
            y: _dragging ? root._dragY : root._yForSlot(_combinedSlot)
            Behavior on y { enabled: !_row._dragging && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            scale: _dragging ? 1.02 : 1.0
            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }

            Accessible.role: Accessible.ListItem
            Accessible.name: _row.meta.label

            RowHoverBg {
                anchors.fill: parent
                cardInset:    2
                topRadius:    10
                bottomRadius: 10
                active:       _row._dragging || _handleHover.hovered || _keyFocus.activeFocus
                fillColor:    _row._dragging ? Theme.accent : Theme.text
                fillOpacity:  _row._dragging ? 0.10 : (_keyFocus.activeFocus ? 0.08 : 0.05)
            }
            // RowHoverBg has no border; the drag-state ring is its own thin overlay.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 8
                antialiasing: true
                color: "transparent"
                visible: _row._dragging
                border.width: 1
                border.color: Theme.withAlpha(Theme.accent, 0.35)
            }

            // Drag handle — the only part of the row that initiates a drag,
            // so tapping the toggle/zone chip elsewhere on the row still works.
            Item {
                id: _handle
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 32

                Text {
                    anchors.centerIn: parent
                    text: "⣿"
                    color: _row._dragging ? Theme.accent : Theme.withAlpha(Theme.subtext, _handleHover.hovered ? 0.75 : 0.45)
                    font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                HoverHandler { id: _handleHover; cursorShape: Qt.OpenHandCursor }
                DragHandler {
                    id: _dragH
                    target: null
                    // Captured once per gesture: DragHandler.translation is
                    // cumulative from the press point, not a per-frame delta.
                    // Re-deriving the base from _row._combinedSlot on every
                    // change (as this used to) re-adds the full cumulative
                    // translation on top of an already-shifted base after
                    // each swap, snowballing the row toward one end.
                    property real _startY: 0
                    onActiveChanged: {
                        if (active) {
                            _dragH._startY = root._yForSlot(_row._combinedSlot)
                            root._draggingKey = _row.key
                            root._dragY = _dragH._startY
                        } else {
                            root._draggingKey = ""
                        }
                    }
                    onTranslationChanged: {
                        if (!active) return
                        const minY = root._yForSlot(0)
                        const maxY = root._yForSlot(root._allKeys.length - 1)
                        root._dragY = Math.max(minY, Math.min(maxY, _dragH._startY + translation.y))
                        const targetSlot = root._slotForY(root._dragY)
                        if (targetSlot === _row._combinedSlot) return
                        const targetZone = targetSlot < root._leftCount ? "left" : "right"
                        const targetIdxInZone = targetZone === "left" ? targetSlot : targetSlot - root._leftCount
                        ShellSettings.setBarWidgetZone(_row.key, targetZone, targetIdxInZone)
                    }
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
                anchors.right: _toggle.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: _row.meta.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: _row._checked ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
            }

            // Show/hide toggle — absent for workspaces (no hide capability).
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

            // Keyboard fallback: focus the row, Ctrl+Up/Down reorders within
            // its current zone (mirrors the drag handle for a11y/no-mouse use).
            FocusScope {
                id: _keyFocus
                anchors.fill: parent
                activeFocusOnTab: true
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
