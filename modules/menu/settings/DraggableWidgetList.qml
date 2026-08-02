pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Item {
    id: root

    readonly property int _toolbarH: 30
    readonly property int _zoneHeaderH: 18
    readonly property int _rowH: 32
    readonly property int _emptyH: 26
    readonly property int _bottomPad: 6
    readonly property var _allKeys: ShellSettings.barWidgetKeys
    readonly property var _zones: ["left", "center", "right"]

    property var _previewLayout: ({ left: [], center: [], right: [], loc: ({}) })
    property string _draggingKey: ""
    property real _dragY: 0
    property string _pendingFocusKey: ""

    readonly property var _leftKeys: _draggingKey.length > 0
        ? _previewLayout.left : ShellSettings.barWidgetOrderLeftKeys
    readonly property var _rightKeys: _draggingKey.length > 0
        ? _previewLayout.right : ShellSettings.barWidgetOrderRightKeys
    readonly property var _centerKeys: _draggingKey.length > 0
        ? _previewLayout.center : ShellSettings.barWidgetOrderCenterKeys
    readonly property int _leftCount: _leftKeys.length
    readonly property int _centerCount: _centerKeys.length
    readonly property int _rightCount: _rightKeys.length
    readonly property bool _leftEmpty: _leftCount === 0
    readonly property bool _centerEmpty: _centerCount === 0
    readonly property bool _rightEmpty: _rightCount === 0
    readonly property int _leftPad: _leftEmpty ? _emptyH : 0
    readonly property int _centerPad: _centerEmpty ? _emptyH : 0
    readonly property int _rightPad: _rightEmpty ? _emptyH : 0
    readonly property int _leftListTop: _toolbarH + _zoneHeaderH
    readonly property int _leftBottom: _leftListTop + _leftCount * _rowH + _leftPad
    readonly property int _centerListTop: _leftBottom + _zoneHeaderH
    readonly property int _centerBottom: _centerListTop + _centerCount * _rowH + _centerPad
    readonly property int _rightListTop: _centerBottom + _zoneHeaderH
    readonly property string _dragZone: _draggingKey.length > 0
        ? _zoneForY(_dragY) : ""
    readonly property int _dragSlot: _combinedSlotOf(_draggingKey)

    width: parent ? parent.width : 0
    height: _rightListTop + _rightCount * _rowH + _rightPad + _bottomPad
    implicitHeight: height

    function _locate(key: string): var {
        if (root._draggingKey.length === 0) return ShellSettings.barWidgetLocate(key)
        return root._previewLayout.loc[key] ?? ({ zone: "", index: -1 })
    }

    function _makePreviewLayout(left, center, right): var {
        const loc = ({})
        for (let i = 0; i < left.length; i++) loc[left[i]] = { zone: "left", index: i }
        for (let i = 0; i < center.length; i++) loc[center[i]] = { zone: "center", index: i }
        for (let i = 0; i < right.length; i++) loc[right[i]] = { zone: "right", index: i }
        return { left: left, center: center, right: right, loc: loc }
    }

    function _combinedSlotOf(key: string): int {
        if (!key) return -1
        const loc = root._locate(key)
        if (loc.index < 0) return -1
        return loc.zone === "left" ? loc.index
            : loc.zone === "center" ? root._leftCount + loc.index
            : root._leftCount + root._centerCount + loc.index
    }

    function _yForSlot(slot: real): real {
        if (slot < root._leftCount)
            return root._leftListTop + slot * root._rowH
        if (slot < root._leftCount + root._centerCount)
            return root._centerListTop + (slot - root._leftCount) * root._rowH
        return root._rightListTop
            + (slot - root._leftCount - root._centerCount) * root._rowH
    }

    function _zoneForY(y: real): string {
        if (y < root._leftBottom + root._zoneHeaderH / 2) return "left"
        if (y < root._centerBottom + root._zoneHeaderH / 2) return "center"
        return "right"
    }

    function _slotForY(y: real): int {
        const zone = root._zoneForY(y)
        if (zone === "left") {
            const idx = Math.round((y - root._leftListTop) / root._rowH)
            return Math.max(0, Math.min(root._leftCount, idx))
        }
        if (zone === "center") {
            const idx = Math.round((y - root._centerListTop) / root._rowH)
            return root._leftCount + Math.max(0, Math.min(root._centerCount, idx))
        }
        const idx = Math.round((y - root._rightListTop) / root._rowH)
        return root._leftCount + root._centerCount
            + Math.max(0, Math.min(root._rightCount, idx))
    }

    function _beginDrag(key: string): void {
        root._previewLayout = root._makePreviewLayout(
            ShellSettings.barWidgetOrderLeftKeys.slice(),
            ShellSettings.barWidgetOrderCenterKeys.slice(),
            ShellSettings.barWidgetOrderRightKeys.slice())
        root._dragY = root._yForSlot(root._combinedSlotOf(key))
        root._draggingKey = key
    }

    function _previewMove(key: string, zone: string, atIndex: int): void {
        const left = root._previewLayout.left.filter(function(k) { return k !== key })
        const center = root._previewLayout.center.filter(function(k) { return k !== key })
        const right = root._previewLayout.right.filter(function(k) { return k !== key })
        const target = zone === "left" ? left : zone === "center" ? center : right
        const clamped = Math.max(0, Math.min(target.length, Math.round(atIndex)))
        target.splice(clamped, 0, key)
        // one assignment keeps every row on the same layout snapshot instead of two binding rounds per drag step
        root._previewLayout = root._makePreviewLayout(left, center, right)
    }

    function _finishDrag(key: string): void {
        if (root._draggingKey !== key) return
        ShellSettings.setBarWidgetLayout(
            root._previewLayout.left, root._previewLayout.center,
            root._previewLayout.right)
        root._draggingKey = ""
        root._previewLayout = ({ left: [], center: [], right: [], loc: ({}) })
    }

    function _moveToZone(key: string, targetZone: string): void {
        const loc = ShellSettings.barWidgetLocate(key)
        if (loc.index < 0 || loc.zone === targetZone) return
        const target = targetZone === "left" ? ShellSettings.barWidgetOrderLeftKeys
            : targetZone === "center" ? ShellSettings.barWidgetOrderCenterKeys
            : ShellSettings.barWidgetOrderRightKeys
        ShellSettings.setBarWidgetZone(key, targetZone,
            Math.min(loc.index, target.length))
        root._queueFocus(key)
    }

    function _focusKey(key: string): void {
        const modelIndex = root._allKeys.indexOf(key)
        const item = modelIndex >= 0 ? _rows.itemAt(modelIndex) : null
        if (item) item.focusRow()
    }

    function _focusRelative(key: string, delta: int): void {
        const ordered = root._leftKeys.concat(root._centerKeys, root._rightKeys)
        const i = ordered.indexOf(key)
        if (i < 0) return
        root._focusKey(ordered[Math.max(0, Math.min(ordered.length - 1, i + delta))])
    }

    function _queueFocus(key: string): void {
        root._pendingFocusKey = key
        _focusDefer.restart()
    }

    Timer {
        id: _focusDefer
        interval: 0
        onTriggered: {
            const key = root._pendingFocusKey
            root._pendingFocusKey = ""
            if (key.length > 0) root._focusKey(key)
        }
    }

    Rectangle {
        id: _surface
        anchors.fill: parent
        radius: Theme.radiusControl
        antialiasing: true
        color: Theme.menuCard

        OutlineBorder {
            radius: _surface.radius
            outlineColor: Theme.menuCardBorder
        }
    }

    Item {
        id: _toolbar
        width: parent.width
        height: root._toolbarH

        ShellText {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: _reset.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Drag to reorder or move between lanes"
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.58)
            font.pixelSize: Settings.fontSize - 2
        }

        ActionButton {
            id: _reset
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 22
            radius: 6
            label: "Reset"
            accessibleName: "Reset bar widgets"
            visible: ShellSettings.barWidgetsModified
            width: visible ? implicitWidth : 0
            onTriggered: {
                const ordered = root._leftKeys.concat(root._centerKeys, root._rightKeys)
                if (ordered.length > 0) root._focusKey(ordered[0])
                ShellSettings.resetBarWidgets()
            }
        }

        Hairline {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            color: Theme.menuDivider
        }
    }

    Repeater {
        model: 3
        delegate: Item {
            id: _zoneHeader
            required property int index
            readonly property string zone: root._zones[index]
            readonly property int count: zone === "left" ? root._leftCount
                : zone === "center" ? root._centerCount : root._rightCount
            readonly property bool hot: root._dragZone === zone

            x: 0
            y: zone === "left" ? root._toolbarH
                : zone === "center" ? root._leftBottom : root._centerBottom
            width: root.width
            height: root._zoneHeaderH

            ShellText {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: (_zoneHeader.zone === "left" ? "Left"
                    : _zoneHeader.zone === "center" ? "Center" : "Right")
                    + " · " + _zoneHeader.count
                color: _zoneHeader.hot
                    ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.54)
                font.pixelSize: Math.max(8, Settings.fontSize - 3)
                font.weight: Font.DemiBold
                ColorFade on color {}
            }

            MotionBehavior on y {
                gate: root._draggingKey.length > 0
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
        MotionBehavior on y {
            gate: root._draggingKey.length > 0
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
            readonly property int combinedSlot: zone === "left" ? zoneIndex
                : zone === "center" ? root._leftCount + zoneIndex
                : root._leftCount + root._centerCount + zoneIndex
            readonly property bool dragging: root._draggingKey === key
            readonly property bool hasToggle: meta.setting.length > 0
            readonly property bool checked: ShellSettings.barWidgetConfiguredVisible(key)

            x: 4
            width: root.width - 8
            height: root._rowH
            z: dragging ? 20 : 1
            y: dragging ? root._dragY : root._yForSlot(combinedSlot)

            function focusRow(): void { _keyFocus.forceActiveFocus() }

            MotionBehavior on y {
                gate: !_row.dragging
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
                        root._beginDrag(_row.key)
                        startY = root._dragY
                    } else {
                        root._finishDrag(_row.key)
                    }
                }

                onTranslationChanged: {
                    if (!active) return
                    const maxY = root._rightEmpty ? root._rightListTop
                        : root._rightListTop + (root._rightCount - 1) * root._rowH
                    root._dragY = Math.max(root._leftListTop,
                        Math.min(maxY, startY + translation.y))

                    const targetZone = root._zoneForY(root._dragY)
                    const slot = root._slotForY(root._dragY)
                    const targetIndex = targetZone === "left" ? slot
                        : targetZone === "center" ? slot - root._leftCount
                        : slot - root._leftCount - root._centerCount
                    if (targetZone !== _row.zone || targetIndex !== _row.zoneIndex)
                        root._previewMove(_row.key, targetZone, targetIndex)
                }
            }

            ShellText {
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
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }

            ShellText {
                anchors.left: _glyph.right
                anchors.leftMargin: 7
                anchors.right: _row.hasToggle ? _toggleTarget.left : parent.right
                anchors.rightMargin: _row.hasToggle ? 4 : 12
                anchors.verticalCenter: parent.verticalCenter
                text: _row.meta.label
                elide: Text.ElideRight
                color: _row.checked ? Theme.text : Theme.withAlpha(Theme.text, 0.48)
                font.pixelSize: Settings.fontSize - 1
                ColorFade on color {}
            }

            Item {
                id: _toggleTarget
                visible: _row.hasToggle
                anchors.right: parent.right
                width: 44
                height: parent.height

                HoverHandler { id: _toggleHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: _toggleTap
                    onTapped: {
                        _toggle.armFlipAnimation()
                        ShellSettings.setBarWidgetConfiguredVisible(
                            _row.key, !_row.checked)
                    }
                }

                ToggleSwitch {
                    id: _toggle
                    anchors.centerIn: parent
                    checked: _row.checked
                    highlighted: _toggleHover.hovered
                    focused: _keyFocus.activeFocus
                    pressed: _toggleTap.pressed
                }
            }

            FocusScope {
                id: _keyFocus
                anchors.fill: parent
                activeFocusOnTab: true

                Accessible.role: _row.hasToggle
                    ? Accessible.Switch : Accessible.ListItem
                Accessible.name: _row.meta.label
                Accessible.checked: _row.checked
                Accessible.description: (_row.zone === "left" ? "Left"
                    : _row.zone === "center" ? "Center" : "Right")
                    + " zone. Arrow keys navigate; Left and Right change zones; Control Up and Down reorder."
                Accessible.onPressAction: activateToggle()
                Accessible.onToggleAction: activateToggle()

                function activateToggle(): bool {
                    if (!_row.hasToggle) return false
                    _toggle.armFlipAnimation()
                    ShellSettings.setBarWidgetConfiguredVisible(
                        _row.key, !_row.checked)
                    return true
                }

                function toggle(event): void {
                    event.accepted = !event.isAutoRepeat && activateToggle()
                }

                function changeZone(delta: int, event): void {
                    const current = root._zones.indexOf(_row.zone)
                    const next = Math.max(0, Math.min(root._zones.length - 1,
                        current + delta))
                    if (next !== current) root._moveToZone(_row.key, root._zones[next])
                    event.accepted = true
                }

                function move(delta: int, event): void {
                    if (event.modifiers & Qt.ControlModifier) {
                        ShellSettings.moveBarWidget(_row.key, delta)
                        root._queueFocus(_row.key)
                    } else {
                        root._focusRelative(_row.key, delta)
                    }
                    event.accepted = true
                }

                Keys.onSpacePressed: event => toggle(event)
                Keys.onReturnPressed: event => toggle(event)
                Keys.onEnterPressed: event => toggle(event)
                Keys.onLeftPressed: event => changeZone(-1, event)
                Keys.onRightPressed: event => changeZone(1, event)
                Keys.onUpPressed: event => move(-1, event)
                Keys.onDownPressed: event => move(1, event)
            }
        }
    }

    Repeater {
        model: 3
        delegate: Rectangle {
            id: _empty
            required property int index
            readonly property string zone: root._zones[index]
            readonly property bool shown: zone === "left" ? root._leftEmpty
                : zone === "center" ? root._centerEmpty : root._rightEmpty
            readonly property bool hot: root._dragZone === zone

            visible: shown
            x: 8
            width: root.width - 16
            y: (zone === "left" ? root._leftListTop
                : zone === "center" ? root._centerListTop
                : root._rightListTop) + 2
            height: root._emptyH - 4
            radius: 8
            antialiasing: true
            color: Theme.withAlpha(Theme.accent, hot ? 0.08 : 0.025)

            OutlineBorder {
                radius: _empty.radius
                outlineColor: Theme.withAlpha(Theme.accent,
                    _empty.hot ? 0.38 : 0.14)
                ColorFade on outlineColor {}
            }

            ShellText {
                anchors.centerIn: parent
                text: "Drop here"
                color: Theme.withAlpha(Theme.subtext, _empty.hot ? 0.70 : 0.46)
                font.pixelSize: Settings.fontSize - 3
            }

            ColorFade on color {}
            MotionBehavior on y {
                gate: root._draggingKey.length > 0
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }
}
