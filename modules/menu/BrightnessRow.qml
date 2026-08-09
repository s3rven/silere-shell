pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    property real topRadius: 0
    property real bottomRadius: 0
    property real cardInset: 1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false
    property int _focusIndex: -1

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5
    onOpenChanged: if (!open) _focusIndex = -1

    function focusPrimary(fromPointer): void {
        if (fromPointer === true) _slider.focusFromPointer()
        else _slider.focusFromKeyboard()
    }

    function closeInline(): bool {
        if (!root.open) return false
        const focusWindow = root.Window.window
        const focusedItem = focusWindow ? focusWindow.activeFocusItem : null
        const restore = ItemTree.isInside(focusedItem, _options)
        // Move focus before disabling the collapsing subtree.
        if (restore) root.focusPrimary(
            focusedItem && focusedItem.pointerFocusActive === true)
        root.open = false
        return restore
    }

    function _focusCurrentDevice(fromPointer: bool): void {
        if (!root.open) return
        for (let i = 0; i < _deviceRepeater.count; i++) {
            const item = _deviceRepeater.itemAt(i)
            if (item && item.active) {
                root._focusIndex = i
                if (fromPointer) item.focusFromPointer()
                else item.focusFromKeyboard()
                return
            }
        }
        const first = _deviceRepeater.itemAt(0)
        if (first) {
            root._focusIndex = 0
            if (fromPointer) first.focusFromPointer()
            else first.focusFromKeyboard()
        }
    }

    function _focusDeviceIndex(index: int): void {
        if (!root.open || _deviceRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_deviceRepeater.count - 1, index))
        const item = _deviceRepeater.itemAt(i)
        if (item) {
            root._focusIndex = i
            item.focusFromKeyboard()
        }
    }

    Connections {
        target: Brightness
        function onDevicesChanged(): void {
            if (Brightness.devices.length <= 1) root.closeInline()
        }
    }

    QuickSlider {
        id: _slider
        width: parent.width
        topRadius: root.topRadius
        bottomRadius: root._optionsShown ? 0 : root.bottomRadius
        cardInset: root.cardInset
        cardLeftBleed: root.cardLeftBleed
        glyph: Brightness.icon
        wheelKey: "brightness"
        accessibleName: "Brightness"
        value: Brightness.pendingPercent / 100
        valueText: Brightness.pendingPercent + "%"
        expandable: Brightness.devices.length > 1
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        expandLabel: "brightness device"
        onExpandToggled: {
            root.open = !root.open
            if (root.open) {
                const fromPointer = _slider.lastExpandFromPointer
                Qt.callLater(function() {
                    root._focusCurrentDevice(fromPointer)
                })
            }
        }
        onMoved: value => Brightness.setPercent(Math.round(value * 100))
    }

    CollapsibleSection {
        id: _options
        y: _slider.height
        width: parent.width
        expanded: root.open

        Column {
            id: _optionColumn
            width: parent.width
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            Repeater {
                id: _deviceRepeater
                model: root._optionsShown ? Brightness.deviceChoices : []

                delegate: InlineOptionRow {
                    id: _option
                    required property var modelData
                    required property int index
                    readonly property bool active: modelData.value === Brightness.deviceChoice

                    width: _optionColumn.width
                    glyph: modelData.value === "" ? "󰘸" : "󰃟"
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active
                    accessibleDescription: active ? "Current brightness device" : "Brightness device"
                    activeFocusOnTab: root.open
                        && _option.index === root._focusIndex
                    onActiveFocusChanged: if (activeFocus) root._focusIndex = _option.index

                    onTriggered: {
                        ShellSettings.brightnessDevice = modelData.value
                        if (_option.lastTriggerFromPointer) _slider.focusFromPointer()
                        else _slider.focusFromKeyboard()
                        root.open = false
                    }
                    Keys.onEscapePressed: event => {
                        _slider.focusFromKeyboard()
                        root.open = false
                        event.accepted = true
                    }
                    Keys.onUpPressed: event => {
                        root._focusDeviceIndex(_option.index - 1)
                        event.accepted = true
                    }
                    Keys.onDownPressed: event => {
                        root._focusDeviceIndex(_option.index + 1)
                        event.accepted = true
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusDeviceIndex(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusDeviceIndex(_deviceRepeater.count - 1)
                            event.accepted = true
                        }
                    }
                }
            }
        }
    }
}
