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

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5

    function _focusCurrentDevice(): void {
        if (!root.open) return
        for (let i = 0; i < _deviceRepeater.count; i++) {
            const item = _deviceRepeater.itemAt(i)
            if (item && item.active) {
                item.forceActiveFocus()
                return
            }
        }
        const first = _deviceRepeater.itemAt(0)
        if (first) first.forceActiveFocus()
    }

    function _focusDeviceIndex(index: int): void {
        if (!root.open || _deviceRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_deviceRepeater.count - 1, index))
        const item = _deviceRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    Connections {
        target: Brightness
        function onDevicesChanged(): void {
            if (Brightness.devices.length <= 1) root.open = false
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
            if (root.open) Qt.callLater(root._focusCurrentDevice)
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

                    onTriggered: {
                        ShellSettings.brightnessDevice = modelData.value
                        root.open = false
                        _slider.forceActiveFocus()
                    }
                    Keys.onEscapePressed: event => {
                        root.open = false
                        _slider.forceActiveFocus()
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
