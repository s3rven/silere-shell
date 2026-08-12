pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Item {
    id: root

    // the page's scroll container, so a drag can reach lanes past the viewport edge
    property Flickable scroller: null

    readonly property int _toolbarH: Metrics.rowHeightFor(32)
    readonly property int _zoneHeaderH: 20
    readonly property int _rowH: Metrics.rowHeightFor(32)
    readonly property int _emptyH: Metrics.rowHeightFor(28)
    readonly property int _bottomPad: 8
    readonly property var _allKeys: ShellSettings.barWidgetKeys
    readonly property var _zones: ["left", "center", "right"]

    property var _previewLayout: ({ left: [], center: [], right: [], loc: ({}) })
    property string _draggingKey: ""
    property real _dragY: 0
    property bool _resetArmed: false

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
        root._dragScrollOffset = 0
        root._autoScrollDir = 0
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

    function _clampDragY(y: real): real {
        const maxY = root._rightEmpty ? root._rightListTop
            : root._rightListTop + (root._rightCount - 1) * root._rowH
        return Math.max(root._leftListTop, Math.min(maxY, y))
    }

    function _applyDragPosition(key: string): void {
        const targetZone = root._zoneForY(root._dragY)
        const slot = root._slotForY(root._dragY)
        const targetIndex = targetZone === "left" ? slot
            : targetZone === "center" ? slot - root._leftCount
            : slot - root._leftCount - root._centerCount
        const loc = root._locate(key)
        if (targetZone !== loc.zone || targetIndex !== loc.index)
            root._previewMove(key, targetZone, targetIndex)
    }

    // the pointer stays put while the view scrolls, so edge distance is measured in the
    // scroller's own coordinates, not the list's
    function _updateAutoScroll(): void {
        const f = root.scroller
        if (!f || root._draggingKey.length === 0) {
            root._autoScrollDir = 0
            return
        }
        const p = root.mapToItem(f, 0, root._dragY + root._rowH / 2)
        root._autoScrollDir = p.y < root._rowH ? -1
            : p.y > f.height - root._rowH ? 1 : 0
    }

    property int _autoScrollDir: 0
    // translation is measured from the grab point, so auto-scrolled distance has to be
    // carried separately or the next pointer move undoes it
    property real _dragScrollOffset: 0

    Timer {
        id: _autoScrollTick
        interval: 16
        repeat: true
        running: root._autoScrollDir !== 0 && root._draggingKey.length > 0
            && root.scroller !== null
        onTriggered: {
            const f = root.scroller
            if (!f) return
            const maxY = Math.max(0, f.contentHeight - f.height)
            const next = Math.max(0, Math.min(maxY, f.contentY + root._autoScrollDir * 6))
            const delta = next - f.contentY
            if (delta === 0) {
                root._autoScrollDir = 0
                return
            }
            f.contentY = next
            // carry the row with the view or it slides out from under the pointer
            root._dragScrollOffset += delta
            root._dragY = root._clampDragY(root._dragY + delta)
            root._applyDragPosition(root._draggingKey)
        }
    }

    function _finishDrag(key: string): void {
        if (root._draggingKey !== key) return
        root._autoScrollDir = 0
        ShellSettings.setBarWidgetLayout(
            root._previewLayout.left, root._previewLayout.center,
            root._previewLayout.right)
        root._draggingKey = ""
        root._previewLayout = ({ left: [], center: [], right: [], loc: ({}) })
    }

    Timer {
        id: _resetArmTimeout
        interval: 3000
        onTriggered: root._resetArmed = false
    }

    Rectangle {
        id: _surface
        anchors.fill: parent
        radius: Theme.radiusCard
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
            text: "Drag to reorder · arrow keys move between lanes"
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.58)
            font.pixelSize: Settings.fontCaption
        }

        ActionButton {
            id: _reset
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: Metrics.rowHeightFor(24)
            label: root._resetArmed ? "Confirm" : "Reset"
            emphasis: root._resetArmed
            accentColor: root._resetArmed ? Theme.warning : Theme.accent
            visible: ShellSettings.barWidgetsModified
            width: visible ? implicitWidth : 0
            onVisibleChanged: if (!visible) {
                _resetArmTimeout.stop()
                root._resetArmed = false
            }
            onTriggered: {
                if (!root._resetArmed) {
                    root._resetArmed = true
                    _resetArmTimeout.restart()
                    return
                }
                _resetArmTimeout.stop()
                root._resetArmed = false
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
                font.pixelSize: Settings.fontMicro
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

            MotionBehavior on y {
                gate: !_row.dragging
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            RowHoverBg {
                anchors.fill: parent
                cardInset: 0
                topRadius: Theme.radiusControl
                bottomRadius: Theme.radiusControl
                active: _row.dragging || _rowHover.hovered
                fillColor: _row.dragging ? Theme.accent : Theme.text
                fillOpacity: _row.dragging ? 0.11 : 0.04
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
                    root._dragY = root._clampDragY(
                        startY + translation.y + root._dragScrollOffset)
                    root._applyDragPosition(_row.key)
                    root._updateAutoScroll()
                }
            }

            ShellText {
                id: _glyph
                visible: root.width >= 180
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 18 : 0
                horizontalAlignment: Text.AlignHCenter
                text: _row.meta.glyph
                color: _row.checked
                    ? Theme.withAlpha(Theme.accent, 0.90)
                    : Theme.withAlpha(Theme.subtext, 0.48)
                font.pixelSize: Settings.iconSize + 2
                ColorFade on color {}
            }

            ShellText {
                anchors.left: _glyph.right
                anchors.leftMargin: 10
                anchors.right: _dragGrip.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: _row.meta.label
                elide: Text.ElideRight
                color: _row.checked ? Theme.text : Theme.withAlpha(Theme.text, 0.48)
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }

            ShellText {
                id: _dragGrip
                anchors.right: _row.hasToggle ? _toggleTarget.left : parent.right
                anchors.rightMargin: _row.hasToggle ? 1 : 9
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: "󰇙"
                color: Theme.withAlpha(Theme.subtext,
                    _row.dragging || _rowHover.hovered ? 0.68 : 0.38)
                font.pixelSize: Settings.fontLabel
                ColorFade on color {}
            }

            Item {
                id: _toggleTarget
                visible: _row.hasToggle
                anchors.right: parent.right
                anchors.rightMargin: 8
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
                    pressed: _toggleTap.pressed
                }
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
            radius: Theme.radiusControl
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
                text: root._draggingKey.length > 0 ? "Drop here" : "Empty"
                color: Theme.withAlpha(Theme.subtext, _empty.hot ? 0.70 : 0.46)
                font.pixelSize: Settings.fontMicro
            }

            ColorFade on color {}
            MotionBehavior on y {
                gate: root._draggingKey.length > 0
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }
}
