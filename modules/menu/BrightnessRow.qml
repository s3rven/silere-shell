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

    function closeInline(): bool {
        if (!root.open) return false
        root.open = false
        return true
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
        value: Brightness.pendingPercent / 100
        valueText: Brightness.pendingPercent + "%"
        expandable: Brightness.devices.length > 1
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        expandLabel: "brightness device"
        onExpandToggled: root.open = !root.open
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

                    onTriggered: {
                        ShellSettings.brightnessDevice = modelData.value
                        root.open = false
                    }
                }
            }
        }
    }
}
