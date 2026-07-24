pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    readonly property int _toolbarH: 34
    readonly property int _zoneHeaderH: 20
    readonly property int _rowH: 36
    readonly property int _emptyH: 30
    readonly property int _bottomPad: 8
    readonly property var _allKeys: ShellSettings._allBarWidgetKeys

    property var _previewLeft: []
    property var _previewRight: []
    property string _draggingKey: ""
    property real _dragY: 0

    readonly property var _leftKeys: _draggingKey.length > 0
        ? _previewLeft : ShellSettings.barWidgetOrderLeftKeys
    readonly property var _rightKeys: _draggingKey.length > 0
        ? _previewRight : ShellSettings.barWidgetOrderRightKeys
    readonly property int _leftCount: _leftKeys.length
    readonly property int _rightCount: _rightKeys.length
    readonly property bool _leftEmpty: _leftCount === 0
    readonly property bool _rightEmpty: _rightCount === 0
    readonly property int _leftPad: _leftEmpty ? _emptyH : 0
    readonly property int _rightPad: _rightEmpty ? _emptyH : 0
    readonly property int _leftListTop: _toolbarH + _zoneHeaderH
    readonly property int _leftBottom: _leftListTop + _leftCount * _rowH + _leftPad
    readonly property int _rightListTop: _leftBottom + _zoneHeaderH
    readonly property string _dragZone: _draggingKey.length > 0 ? _zoneForY(_dragY) : ""
    readonly property int _dragSlot: _combinedSlotOf(_draggingKey)

    width: parent ? parent.width : 0
    height: _rightListTop + _rightCount * _rowH + _rightPad + _bottomPad
    implicitHeight: height
    Behavior on height {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }

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

    function _yForSlot(slot: real): real {
        return slot < root._leftCount
            ? root._leftListTop + slot * root._rowH
            : root._rightListTop + (slot - root._leftCount) * root._rowH
    }

    function _zoneForY(y: real): string {
        return y < root._leftBottom + root._zoneHeaderH / 2 ? "left" : "right"
    }

    function _slotForY(y: real): int {
        if (root._zoneForY(y) === "left") {
            const idx = Math.round((y - root._leftListTop) / root._rowH)
            return Math.max(0, Math.min(root._leftCount, idx))
        }
        const idx = Math.round((y - root._rightListTop) / root._rowH)
        return root._leftCount + Math.max(0, Math.min(root._rightCount, idx))
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

    function _moveToOtherSide(key: string): void {
        const loc = ShellSettings.barWidgetLocate(key)
        if (loc.index < 0) return
        const targetZone = loc.zone === "left" ? "right" : "left"
        const target = targetZone === "left"
            ? ShellSettings.barWidgetOrderLeftKeys
            : ShellSettings.barWidgetOrderRightKeys
        ShellSettings.setBarWidgetZone(key, targetZone,
            Math.min(loc.index, target.length))
        Qt.callLater(function() { root._focusKey(key) })
    }

    function _focusKey(key: string): void {
        const modelIndex = root._allKeys.indexOf(key)
        const item = modelIndex >= 0 ? _rows.itemAt(modelIndex) : null
        if (item) item.focusRow()
    }

    function _focusRelative(key: string, delta: int): void {
        const ordered = root._leftKeys.concat(root._rightKeys)
        const i = ordered.indexOf(key)
        if (i < 0) return
        root._focusKey(ordered[Math.max(0, Math.min(ordered.length - 1, i + delta))])
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        antialiasing: true
        color: Theme.menuCard
        border.width: 1
        border.color: Theme.menuCardBorder
    }

    Item {
        id: _toolbar
        width: parent.width
        height: root._toolbarH

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: _reset.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Drag rows to arrange"
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.58)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize - 2
            renderType: Text.NativeRendering
        }

        Item {
            id: _reset
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 28
            activeFocusOnTab: true

            Accessible.role: Accessible.Button
            Accessible.name: "Reset bar widgets"
            Accessible.onPressAction: ShellSettings.resetBarWidgets()
            Keys.onSpacePressed: event => {
                if (!event.isAutoRepeat) ShellSettings.resetBarWidgets()
                event.accepted = true
            }
            Keys.onReturnPressed: event => {
                if (!event.isAutoRepeat) ShellSettings.resetBarWidgets()
                event.accepted = true
            }
            Keys.onEnterPressed: event => {
                if (!event.isAutoRepeat) ShellSettings.resetBarWidgets()
                event.accepted = true
            }
            HoverHandler {
                id: _resetHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler { onTapped: ShellSettings.resetBarWidgets() }

            Text {
                anchors.centerIn: parent
                text: "Reset"
                color: _reset.activeFocus || _resetHover.hovered
                    ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.62)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 2
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Rectangle {
                visible: _reset.activeFocus
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                radius: 1
                color: Theme.accent
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.menuDivider
        }
    }

    Repeater {
        model: 2
        delegate: Item {
            id: _zoneHeader
            required property int index
            readonly property bool isLeft: index === 0
            readonly property bool hot: root._dragZone === (isLeft ? "left" : "right")

            x: 0
            y: isLeft ? root._toolbarH : root._leftBottom
            width: root.width
            height: root._zoneHeaderH

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: _zoneHeader.isLeft ? "Left side" : "Right side"
                color: _zoneHeader.hot
                    ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.54)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 2
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Behavior on y {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        visible: root._dragSlot >= 0
        x: 12
        width: root.width - 24
        y: visible ? root._yForSlot(root._dragSlot) - 1 : root._dragY - 1
        height: 2
        radius: 1
        z: 25
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, 0.82)
        Behavior on y {
            enabled: root._draggingKey.length > 0 && !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    Repeater {
        id: _rows
        model: root._allKeys

        delegate: Item {
            id: _row
            required property string modelData

            readonly property string key: modelData
            readonly property var meta: ShellSettings.barWidgetMeta[key]
            readonly property var loc: root._locate(key)
            readonly property string zone: loc.zone
            readonly property int zoneIndex: loc.index
            readonly property int combinedSlot: zone === "left"
                ? zoneIndex : root._leftCount + zoneIndex
            readonly property bool dragging: root._draggingKey === key
            readonly property bool hasToggle: meta.setting.length > 0
            readonly property bool checked: hasToggle ? ShellSettings[meta.setting] : true

            x: 4
            width: root.width - 8
            height: root._rowH
            z: dragging ? 20 : 1
            y: dragging ? root._dragY : root._yForSlot(combinedSlot)

            function focusRow(): void { _keyFocus.forceActiveFocus() }

            Behavior on y {
                enabled: !_row.dragging && !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }

            RowHoverBg {
                anchors.fill: parent
                cardInset: 0
                topRadius: 8
                bottomRadius: 8
                active: _row.dragging || _rowHover.hovered || _keyFocus.activeFocus
                focusActive: _keyFocus.activeFocus
                fillColor: _row.dragging ? Theme.accent : Theme.text
                fillOpacity: _row.dragging ? 0.11
                    : (_keyFocus.activeFocus ? 0.07 : 0.04)
            }

            HoverHandler {
                id: _rowHover
                cursorShape: _drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

            DragHandler {
                id: _drag
                target: null
                property real startY: 0

                onActiveChanged: {
                    if (active) {
                        startY = root._yForSlot(_row.combinedSlot)
                        root._dragY = startY
                        root._beginDrag(_row.key)
                    } else {
                        root._finishDrag(_row.key)
                    }
                }

                onTranslationChanged: {
                    if (!active) return
                    const maxY = root._rightEmpty
                        ? root._rightListTop
                        : root._rightListTop + (root._rightCount - 1) * root._rowH
                    root._dragY = Math.max(root._leftListTop,
                        Math.min(maxY, startY + translation.y))

                    const targetZone = root._zoneForY(root._dragY)
                    const slot = root._slotForY(root._dragY)
                    const targetIndex = targetZone === "left"
                        ? slot : slot - root._leftCount
                    if (targetZone !== _row.zone || targetIndex !== _row.zoneIndex)
                        root._previewMove(_row.key, targetZone, targetIndex)
                }
            }

            Text {
                id: _glyph
                visible: root.width >= 180
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 18 : 0
                horizontalAlignment: Text.AlignHCenter
                text: _row.meta.glyph
                color: _row.checked
                    ? Theme.withAlpha(Theme.accent, 0.90)
                    : Theme.withAlpha(Theme.subtext, 0.48)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 1
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                anchors.left: _glyph.right
                anchors.leftMargin: 7
                anchors.right: _row.hasToggle ? _toggleTarget.left : parent.right
                anchors.rightMargin: _row.hasToggle ? 4 : 12
                anchors.verticalCenter: parent.verticalCenter
                text: _row.meta.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: _row.checked ? Theme.text : Theme.withAlpha(Theme.text, 0.48)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Item {
                id: _toggleTarget
                visible: _row.hasToggle
                anchors.right: parent.right
                width: 44
                height: parent.height

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        _toggle.armFlipAnimation()
                        ShellSettings[_row.meta.setting] = !ShellSettings[_row.meta.setting]
                    }
                }

                ToggleSwitch {
                    id: _toggle
                    anchors.centerIn: parent
                    checked: _row.checked
                }
            }

            FocusScope {
                id: _keyFocus
                anchors.fill: parent
                activeFocusOnTab: true

                Accessible.role: _row.hasToggle
                    ? Accessible.CheckBox : Accessible.ListItem
                Accessible.name: _row.meta.label
                Accessible.checked: _row.checked
                Accessible.description: (_row.zone === "left" ? "Left" : "Right")
                    + " side. Arrow keys navigate; Left and Right change sides; Control Up and Down reorder."
                Accessible.onPressAction: activateToggle()

                function activateToggle(): bool {
                    if (!_row.hasToggle) return false
                    _toggle.armFlipAnimation()
                    ShellSettings[_row.meta.setting] = !ShellSettings[_row.meta.setting]
                    return true
                }

                function toggle(event): void {
                    event.accepted = !event.isAutoRepeat && activateToggle()
                }

                function changeSide(zone: string, event): void {
                    if (_row.zone !== zone) root._moveToOtherSide(_row.key)
                    event.accepted = true
                }

                function move(delta: int, event): void {
                    if (event.modifiers & Qt.ControlModifier) {
                        ShellSettings.moveBarWidget(_row.key, delta)
                        Qt.callLater(function() { root._focusKey(_row.key) })
                    } else {
                        root._focusRelative(_row.key, delta)
                    }
                    event.accepted = true
                }

                Keys.onSpacePressed: event => toggle(event)
                Keys.onReturnPressed: event => toggle(event)
                Keys.onEnterPressed: event => toggle(event)
                Keys.onLeftPressed: event => changeSide("left", event)
                Keys.onRightPressed: event => changeSide("right", event)
                Keys.onUpPressed: event => move(-1, event)
                Keys.onDownPressed: event => move(1, event)
            }
        }
    }

    Repeater {
        model: 2
        delegate: Rectangle {
            id: _empty
            required property int index
            readonly property bool isLeft: index === 0
            readonly property bool shown: isLeft ? root._leftEmpty : root._rightEmpty
            readonly property bool hot: root._dragZone === (isLeft ? "left" : "right")

            visible: shown
            x: 8
            width: root.width - 16
            y: (isLeft ? root._leftListTop : root._rightListTop) + 2
            height: root._emptyH - 4
            radius: 8
            antialiasing: true
            color: Theme.withAlpha(Theme.accent, hot ? 0.08 : 0.025)
            border.width: 1
            border.color: Theme.withAlpha(Theme.accent, hot ? 0.38 : 0.14)

            Text {
                anchors.centerIn: parent
                text: "Drop here"
                color: Theme.withAlpha(Theme.subtext, _empty.hot ? 0.70 : 0.46)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 3
                renderType: Text.NativeRendering
            }

            Behavior on y {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        }
    }
}
