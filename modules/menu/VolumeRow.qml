pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false
    property int _focusIndex: -1

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5
    onOpenChanged: if (!open) _focusIndex = -1

    function _ownsItem(item, ancestor): bool {
        let current = item
        while (current) {
            if (current === ancestor) return true
            current = current.parent
        }
        return false
    }

    function focusPrimary(fromPointer): void {
        if (fromPointer === true) _slider.focusFromPointer()
        else _slider.focusFromKeyboard()
    }

    function closeInline(): bool {
        if (!root.open) return false
        const focusWindow = root.Window.window
        const focusedItem = focusWindow ? focusWindow.activeFocusItem : null
        const restore = root._ownsItem(focusedItem, _options)
        // Move focus before disabling the collapsing subtree.
        if (restore) root.focusPrimary(
            focusedItem && focusedItem.pointerFocusActive === true)
        root.open = false
        return restore
    }

    function _focusCurrentSink(fromPointer: bool): void {
        if (!root.open) return
        for (let i = 0; i < _sinkRepeater.count; i++) {
            const item = _sinkRepeater.itemAt(i)
            if (item && item.active) {
                root._focusIndex = i
                if (fromPointer) item.focusFromPointer()
                else item.focusFromKeyboard()
                return
            }
        }
        const first = _sinkRepeater.itemAt(0)
        if (first) {
            root._focusIndex = 0
            if (fromPointer) first.focusFromPointer()
            else first.focusFromKeyboard()
        }
    }

    function _focusSinkIndex(index: int): void {
        if (!root.open || _sinkRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_sinkRepeater.count - 1, index))
        const item = _sinkRepeater.itemAt(i)
        if (item) {
            root._focusIndex = i
            item.focusFromKeyboard()
        }
    }

    Connections {
        target: Audio
        function onSinkCountChanged() {
            if (Audio.sinkCount <= 1) root.closeInline()
        }
    }

    QuickSlider {
        id: _slider
        y: 0
        width: parent.width
        topRadius:    root.topRadius
        bottomRadius: root._optionsShown ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        cardLeftBleed: root.cardLeftBleed
        glyph: Audio.icon
        wheelKey: "volume"
        accessibleName: "Volume"
        value: Audio.uiVolume
        valueText: Audio.label
        glyphClickable: true
        glyphActionName: Audio.muted ? "Unmute" : "Mute"
        expandable: Audio.sinkCount > 1
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onGlyphClicked: Audio.toggleMute()
        onExpandToggled: {
            root.open = !root.open
            if (root.open) {
                const fromPointer = _slider.lastExpandFromPointer
                Qt.callLater(function() {
                    root._focusCurrentSink(fromPointer)
                })
            }
        }
        onMoved: (v) => Audio.setVolume(v)
    }

    CollapsibleSection {
        id: _options
        y: _slider.height
        width: parent.width
        expanded: root.open

        Column {
            id: _optCol
            width: parent.width
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            Repeater {
                id: _sinkRepeater
                model: root._optionsShown ? Audio.sinkModel : []
                delegate: InlineOptionRow {
                    id: _opt
                    required property var modelData
                    required property int index
                    readonly property bool active: modelData.value === Audio.sink

                    width: _optCol.width
                    glyph: "󰓃"
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active
                    accessibleDescription: active ? "Current output" : "Output device"

                    function _choose(): void {
                        Audio.setSink(_opt.modelData.value)
                        if (_opt.lastTriggerFromPointer) _slider.focusFromPointer()
                        else _slider.focusFromKeyboard()
                        root.open = false
                    }

                    activeFocusOnTab: root.open
                        && _opt.index === root._focusIndex
                    onActiveFocusChanged: if (activeFocus) root._focusIndex = _opt.index
                    onTriggered: _choose()
                    Keys.onEscapePressed: event => {
                        _slider.focusFromKeyboard()
                        root.open = false
                        event.accepted = true
                    }
                    Keys.onUpPressed:     event => { root._focusSinkIndex(_opt.index - 1); event.accepted = true }
                    Keys.onDownPressed:   event => { root._focusSinkIndex(_opt.index + 1); event.accepted = true }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusSinkIndex(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusSinkIndex(_sinkRepeater.count - 1)
                            event.accepted = true
                        }
                    }
                }
            }
        }
    }
}
