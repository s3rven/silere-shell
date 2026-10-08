pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Item {
    id: root

    // the page's scroll container, so a drag can reach lanes past the viewport edge
    property Flickable scroller: null
    property var trayItems: SystemTray.items.values

    readonly property int _toolbarH: Metrics.rowHeightFor(32)
    readonly property int _zoneHeaderH: 20
    readonly property int _rowH: Metrics.rowHeightFor(32)
    readonly property int _emptyH: Metrics.rowHeightFor(28)
    readonly property int _bottomPad: 8
    readonly property var _allKeys: ShellSettings.barWidgetKeys
    readonly property var _zones: ["left", "center", "right"]

    signal flipsArmed()

    readonly property int _traySubH: Metrics.rowHeightFor(28)
    readonly property int _trayPadBottom: 4
    property bool _trayOpen: false
    property real _trayReveal: 0
    readonly property bool _trayMotionAllowed: Motion.allowsMotion(
        Idle.isIdle, ShellSettings.reduceMotion)
    on_TrayMotionAllowedChanged: if (!root._trayMotionAllowed) {
        _trayRevealAnim.stop()
        root._trayReveal = root._trayOpen ? 1 : 0
    }
    // ids toggled while open stay listed, so un-hiding an app that is not running cannot pull its row out from under the pointer
    property var _trayStickyIds: []
    readonly property var _trayItemById: {
        const m = Object.create(null)
        const items = root.trayItems
        for (let i = 0; i < items.length; i++) {
            const id = String(items[i]?.id || "")
            if (id.length > 0 && !m[id]) m[id] = items[i]
        }
        return m
    }
    readonly property var _trayIds: {
        const out = []
        const items = root.trayItems
        for (let i = 0; i < items.length; i++) {
            const id = String(items[i]?.id || "")
            if (id.length > 0 && out.indexOf(id) < 0) out.push(id)
        }
        const extra = ShellSettings.trayHiddenIds.concat(root._trayStickyIds)
        for (let i = 0; i < extra.length; i++)
            if (out.indexOf(extra[i]) < 0) out.push(extra[i])
        return out
    }
    readonly property int _trayPanelH: root._trayIds.length > 0
        ? root._trayIds.length * root._traySubH + root._trayPadBottom
            + (ShellSettings.trayHiddenIds.length > 0 ? root._traySubH : 0)
        : root._emptyH
    readonly property real _trayExtra: root._trayPanelH * root._trayReveal
    readonly property string _trayZone: root._locate("tray").zone
    readonly property int _traySlot: root._combinedSlotOf("tray")

    property var _previewLayout: ({ left: [], center: [], right: [], loc: ({}) })
    property string _draggingKey: ""
    property real _dragY: 0

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
    readonly property real _leftBottom: _leftListTop + _leftCount * _rowH + _leftPad
        + (_trayZone === "left" ? _trayExtra : 0)
    readonly property real _centerListTop: _leftBottom + _zoneHeaderH
    readonly property real _centerBottom: _centerListTop + _centerCount * _rowH + _centerPad
        + (_trayZone === "center" ? _trayExtra : 0)
    readonly property real _rightListTop: _centerBottom + _zoneHeaderH
    readonly property string _dragZone: _draggingKey.length > 0
        ? _zoneForY(_dragY) : ""
    readonly property int _dragSlot: _combinedSlotOf(_draggingKey)

    width: parent ? parent.width : 0
    height: _rightListTop + _rightCount * _rowH + _rightPad + _bottomPad
        + (_trayZone === "right" ? _trayExtra : 0)
    implicitHeight: height

    MotionBehavior on height {
        gate: !_trayRevealAnim.running
        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
    }

    function _noteFor(key: string): string {
        switch (key) {
        case "battery":
            if (Battery.upowerReady && !Battery.present) return "No battery"
            return ShellSettings.batteryAutoHide ? "When unplugged" : ""
        case "bluetooth":
            return Bluetooth.available ? "" : "No adapter"
        case "brightness":
            if (!SystemTools.ready || Brightness.controllable) return ""
            return Brightness.toolAvailable ? "No backlight" : "No brightnessctl"
        case "microphone": return "While in use"
        case "media": return "While playing"
        case "shellUpdate":
        case "updates": return "When pending"
        case "tray": {
            const n = ShellSettings.trayHiddenIds.length
            if (n > 0) return n + " hidden"
            return root.trayItems.length === 0 ? "No apps running" : ""
        }
        }
        return ""
    }

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
        const below = slot > root._traySlot ? root._trayExtra : 0
        if (slot < root._leftCount)
            return root._leftListTop + slot * root._rowH
                + (root._trayZone === "left" ? below : 0)
        if (slot < root._leftCount + root._centerCount)
            return root._centerListTop + (slot - root._leftCount) * root._rowH
                + (root._trayZone === "center" ? below : 0)
        return root._rightListTop
            + (slot - root._leftCount - root._centerCount) * root._rowH
            + (root._trayZone === "right" ? below : 0)
    }

    // index the dragged row would take in a zone; an open tray panel sits between the tray and the row after it
    function _zoneIndexForY(zone: string, keys: var, rel: real): int {
        let idx = Math.round(rel / root._rowH)
        if (zone === root._trayZone && root._trayExtra > 0) {
            const t = keys.filter(k => k !== root._draggingKey).indexOf("tray")
            if (t >= 0)
                idx = rel < (t + 0.5) * root._rowH + root._trayExtra / 2
                    ? Math.min(t, idx)
                    : Math.max(t + 1, Math.round((rel - root._trayExtra) / root._rowH))
        }
        return Math.max(0, Math.min(keys.length, idx))
    }

    function _zoneForY(y: real): string {
        if (y < root._leftBottom + root._zoneHeaderH / 2) return "left"
        if (y < root._centerBottom + root._zoneHeaderH / 2) return "center"
        return "right"
    }

    function _slotForY(y: real): int {
        const zone = root._zoneForY(y)
        if (zone === "left")
            return root._zoneIndexForY("left", root._leftKeys, y - root._leftListTop)
        if (zone === "center")
            return root._leftCount
                + root._zoneIndexForY("center", root._centerKeys, y - root._centerListTop)
        return root._leftCount + root._centerCount
            + root._zoneIndexForY("right", root._rightKeys, y - root._rightListTop)
    }

    function _setTrayOpen(open: bool): void {
        if (root._trayOpen === open) return
        root._trayOpen = open
        if (open) root._trayStickyIds = []
        _trayRevealAnim.stop()
        if (!root._trayMotionAllowed) {
            root._trayReveal = open ? 1 : 0
            return
        }
        _trayRevealAnim.to = open ? 1 : 0
        _trayRevealAnim.duration = open ? Motion.medium : Motion.fast
        _trayRevealAnim.easing.bezierCurve = open ? Motion.emphasizedDecel : Motion.emphasizedAccel
        _trayRevealAnim.start()
    }

    function _setTrayItemShown(id: string, shown: bool): void {
        if (root._trayStickyIds.indexOf(id) < 0)
            root._trayStickyIds = root._trayStickyIds.concat([id])
        ShellSettings.setTrayItemHidden(id, !shown)
        if (shown) ShellSettings.trayWidget = true
    }

    function _showAllTrayItems(): void {
        root._trayStickyIds = root._trayStickyIds.concat(ShellSettings.trayHiddenIds
            .filter(id => root._trayStickyIds.indexOf(id) < 0))
        root.flipsArmed()
        ShellSettings.trayHidden = ""
        ShellSettings.trayWidget = true
    }

    function _resetAll(): void {
        root._trayStickyIds = root._trayStickyIds.concat(ShellSettings.trayHiddenIds
            .filter(id => root._trayStickyIds.indexOf(id) < 0))
        root.flipsArmed()
        ShellSettings.resetBarWidgets()
    }

    // rows, headers and the card height read the reveal every frame; their own Behaviors stand down while it runs
    NumberAnimation {
        id: _trayRevealAnim
        target: root
        property: "_trayReveal"
        easing.type: Easing.BezierSpline
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
        if (key === "tray" && root._trayReveal > 0) {
            _trayRevealAnim.stop()
            root._trayOpen = false
            root._trayReveal = 0
        }
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
                + (root._trayZone === "right" ? root._trayExtra : 0)
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

    // the pointer stays put while the view scrolls, so edge distance is measured in the scroller's own coordinates, not the list's
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
    // translation is measured from the grab point, so auto-scrolled distance has to be carried separately or the next pointer move undoes it
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
            // the shell is pointer-only; this used to promise arrow keys that no longer move anything
            text: "Drag to reorder · toggle to show or hide"
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.58)
            font.pixelSize: Settings.fontCaption
        }

        ConfirmButton {
            id: _reset
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            designHeight: 24
            glyph: "󰦛"
            label: "Reset"
            tint: Theme.warning
            shown: ShellSettings.barWidgetsModified
            onConfirmed: root._resetAll()
        }

        Hairline {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
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
            readonly property var keys: zone === "left" ? root._leftKeys
                : zone === "center" ? root._centerKeys : root._rightKeys
            readonly property int shown: keys.filter(k => ShellSettings.barWidgetConfiguredVisible(k)).length
            readonly property bool hot: root._dragZone === zone

            x: 0
            y: zone === "left" ? root._toolbarH
                : zone === "center" ? root._leftBottom : root._centerBottom
            width: root.width
            height: root._zoneHeaderH

            ShellText {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                text: (_zoneHeader.zone === "left" ? "Left"
                    : _zoneHeader.zone === "center" ? "Center" : "Right")
                    + " · " + _zoneHeader.shown + " shown"
                color: _zoneHeader.hot
                    ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.54)
                font.pixelSize: Settings.fontMicro
                font.weight: Font.DemiBold
                ColorFade on color {}
            }

            MotionBehavior on y {
                gate: !_trayRevealAnim.running
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        id: _dropSlot
        visible: root._dragSlot >= 0
        x: 4
        width: root.width - 8
        y: visible ? root._yForSlot(root._dragSlot) : root._dragY
        height: root._rowH
        radius: Theme.radiusControl
        antialiasing: true
        color: Theme.withAlpha(Theme.accent, 0.10)

        OutlineBorder {
            radius: _dropSlot.radius
            outlineColor: Theme.withAlpha(Theme.accent, 0.42)
        }

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
            readonly property string note: checked ? root._noteFor(key) : ""
            readonly property bool isTray: key === "tray"

            x: 4
            width: root.width - 8
            height: root._rowH
            z: dragging ? 20 : 1
            y: dragging ? root._dragY : root._yForSlot(combinedSlot)

            MotionBehavior on y {
                gate: !_row.dragging && !_trayRevealAnim.running
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }

            Connections {
                target: root
                function onFlipsArmed() { _toggle.armFlipAnimation() }
            }

            TapHandler {
                enabled: _row.isTray
                onTapped: (point) => {
                    if (point.position.x < _toggleTarget.x)
                        root._setTrayOpen(!root._trayOpen)
                }
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
                anchors.right: _note.left
                anchors.rightMargin: _note.text.length > 0 ? 8 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: _row.meta.label
                elide: Text.ElideRight
                color: _row.checked ? Theme.text : Theme.withAlpha(Theme.text, 0.48)
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }

            ShellText {
                id: _note
                anchors.right: _chevron.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: _row.note
                color: Theme.menuTextDetail
                font.pixelSize: Settings.fontCaption
            }

            Item {
                id: _chevron
                visible: _row.isTray
                anchors.right: _dragGrip.left
                width: visible ? 22 : 0
                height: parent.height

                ShellText {
                    anchors.centerIn: parent
                    text: "󰅀"
                    rotation: root._trayOpen ? 180 : 0
                    transformOrigin: Item.Center
                    color: _chevHover.hovered ? Theme.text
                        : Theme.withAlpha(Theme.subtext, root._trayOpen ? 0.85 : 0.55)
                    font.pixelSize: Settings.fontSize
                    Disclosure on rotation {}
                    ColorFade on color {}
                }

                HoverHandler { id: _chevHover; cursorShape: Qt.PointingHandCursor }
            }

            Loader {
                active: _row.isTray
                y: root._rowH
                width: parent.width
                height: root._trayExtra
                visible: root._trayExtra > 0.5
                enabled: root._trayOpen && root._draggingKey.length === 0
                clip: true
                opacity: root._trayReveal
                sourceComponent: _trayPanel
            }

            ShellText {
                id: _dragGrip
                // _toggleTarget keeps its geometry while hidden, so the grip holds one column on every row
                anchors.right: _toggleTarget.left
                anchors.rightMargin: 1
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
                enabled: _row.hasToggle && root._draggingKey.length === 0
                anchors.right: parent.right
                anchors.rightMargin: 8
                width: 44
                height: parent.height

                Accessible.role: Accessible.CheckBox
                Accessible.name: _row.meta.label
                Accessible.description: _row.note
                Accessible.checkable: true
                Accessible.checked: _row.checked
                Accessible.focusable: enabled
                Accessible.onPressAction: _toggleTap.activate()
                Accessible.onToggleAction: _toggleTap.activate()

                HoverHandler { id: _toggleHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: _toggleTap
                    function activate(): void {
                        if (!_toggleTarget.enabled || !_toggleTarget.visible) return
                        _toggle.armFlipAnimation()
                        ShellSettings.setBarWidgetConfiguredVisible(
                            _row.key, !_row.checked)
                    }
                    onTapped: _toggleTap.activate()
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
                gate: !_trayRevealAnim.running
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
        }
    }

    Component {
        id: _trayPanel

        Item {
            opacity: ShellSettings.trayWidget ? 1.0 : Theme.disabledOpacity
            MotionBehavior on opacity {NumberAnimation { duration: Motion.color } }

            ShellText {
                visible: root._trayIds.length === 0
                x: 38
                height: root._emptyH
                verticalAlignment: Text.AlignVCenter
                text: "No tray apps running"
                color: Theme.withAlpha(Theme.subtext, 0.46)
                font.pixelSize: Settings.fontCaption
            }

            Column {
                width: parent.width

                Repeater {
                    model: root._trayIds

                    delegate: Item {
                        id: _sub
                        required property string modelData
                        readonly property var item: root._trayItemById[modelData] ?? null
                        readonly property bool running: item !== null
                        readonly property string _providedIconSource: _sub.running
                            ? IconResolver.trayIconSource(_sub.item.icon) : ""
                        property bool _providedIconFailed: false
                        on_ProvidedIconSourceChanged: _sub._providedIconFailed = false
                        readonly property bool checked: !ShellSettings.trayItemHidden(modelData)
                        readonly property string statusText: !_sub.running ? "Not running"
                            : !_sub.checked ? "Hidden"
                            : !ShellSettings.trayWidget ? "Tray off" : "Shown"
                        readonly property string label: !running ? modelData
                            : SafeText.singleLineText(
                                String(item.title || "").length > 0 ? item.title
                                : String(item.tooltipTitle || "").length > 0 ? item.tooltipTitle
                                : modelData, 128)

                        width: parent.width
                        height: root._traySubH

                        function toggleShown(): void {
                            if (!_sub.enabled || !_sub.visible) return
                            _subToggle.armFlipAnimation()
                            root._setTrayItemShown(_sub.modelData,
                                !ShellSettings.trayWidget || !_sub.checked)
                        }

                        Accessible.role: Accessible.CheckBox
                        Accessible.name: _sub.label
                        Accessible.description: _sub.statusText
                        Accessible.checkable: true
                        Accessible.checked: _sub.checked && ShellSettings.trayWidget
                        Accessible.focusable: enabled
                        Accessible.onPressAction: _sub.toggleShown()
                        Accessible.onToggleAction: _sub.toggleShown()

                        Connections {
                            target: root
                            function onFlipsArmed() { _subToggle.armFlipAnimation() }
                        }

                        RowHoverBg {
                            anchors.fill: parent
                            cardInset: 0
                            topRadius: Theme.radiusControl
                            bottomRadius: Theme.radiusControl
                            active: _subHover.hovered
                            fillColor: Theme.text
                            fillOpacity: 0.04
                        }

                        HoverHandler { id: _subHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: _subTap
                            onTapped: _sub.toggleShown()
                        }

                        Item {
                            id: _subIcon
                            x: 38
                            anchors.verticalCenter: parent.verticalCenter
                            width: Settings.iconSize + 4
                            height: width
                            opacity: _sub.checked ? 1.0 : 0.45
                            MotionBehavior on opacity {NumberAnimation { duration: Motion.color } }

                            IconImage {
                                id: _subImage
                                anchors.fill: parent
                                readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                                transform: PixelSnap { item: _subImage; dpr: _subImage._dpr }
                                source: IconResolver.trayAppIconSource(
                                    _sub._providedIconFailed ? "" : _sub._providedIconSource, _sub.modelData)
                                implicitSize: parent.width
                                asynchronous: true
                                backer.cache: false
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status === Image.Error && !_sub._providedIconFailed
                                            && _sub._providedIconSource.length > 0)
                                        _sub._providedIconFailed = true
                                }
                            }

                            ShellText {
                                anchors.centerIn: parent
                                visible: !_subImage.visible
                                text: SafeText.initial(_sub.label, "?")
                                color: Theme.subtext
                                font.pixelSize: Settings.fontCaption
                            }
                        }

                        ShellText {
                            anchors.left: _subIcon.right
                            anchors.leftMargin: 10
                            anchors.right: _subNote.left
                            anchors.rightMargin: _subNote.text.length > 0 ? 8 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: _sub.label
                            elide: Text.ElideRight
                            color: _sub.checked
                                ? Theme.withAlpha(Theme.text, 0.86) : Theme.withAlpha(Theme.text, 0.48)
                            font.pixelSize: Settings.fontLabel
                            ColorFade on color {}
                        }

                        ShellText {
                            id: _subNote
                            anchors.right: _subToggleTarget.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: _sub.statusText
                            color: Theme.menuTextDetail
                            font.pixelSize: Settings.fontCaption
                        }

                        Item {
                            id: _subToggleTarget
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            width: 44
                            height: parent.height

                            ToggleSwitch {
                                id: _subToggle
                                anchors.centerIn: parent
                                checked: _sub.checked && ShellSettings.trayWidget
                                highlighted: _subHover.hovered
                                pressed: _subTap.pressed
                            }
                        }
                    }
                }

                InlineOptionRow {
                    visible: ShellSettings.trayHiddenIds.length > 0
                    width: parent.width
                    height: root._traySubH
                    glyph: "󰈈"
                    label: "Show all apps"
                    onTriggered: root._showAllTrayItems()
                }
            }
        }
    }
}
