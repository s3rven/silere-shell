pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "controls"

Column {
    id: root

    width: parent ? parent.width : 0
    property var readings: Battery.details

    // built as the details open: a limit changed meanwhile, by the firmware too, shows as it is now
    Component.onCompleted: BatteryLimit.refresh()

    Repeater {
        model: root.readings

        Column {
            id: device
            required property var modelData
            width: root.width
            readonly property var limit: BatteryLimit.forNative(device.modelData.nativePath)
            readonly property bool _writing: BatteryLimit.pendingNative.length > 0
                && BatteryLimit.pendingNative === device.modelData.nativePath

            ControlRow {
                // one battery is the Battery reading right above: same name, charge and state
                visible: root.readings.length > 1
                glyph: "󰁹"
                title: device.modelData.name
                status: [device.modelData.model, device.modelData.state].filter(s => s.length > 0).join(" · ")
                valueText: device.modelData.charge
                passive: true
            }
            ControlRow {
                visible: device.modelData.health.length > 0
                glyph: "󰣐"
                title: "Battery health"
                status: "Compared with original capacity"
                valueText: device.modelData.health
                passive: true
            }
            ControlRow {
                visible: device.modelData.energy.length > 0
                glyph: "󱊣"
                title: "Energy"
                status: "Stored / full: " + device.modelData.energy
                passive: true
            }
            ControlRow {
                visible: device.modelData.power.length > 0
                glyph: "󱐋"
                title: device.modelData.powerLabel
                valueText: device.modelData.power
                passive: true
            }
            ToggleRow {
                id: _limitRow
                visible: device.limit !== null
                glyph: "󱈑"
                label: "Charge limit"
                description: BatteryLimit.describe(device.limit)
                checked: device._writing ? BatteryLimit.pendingOn : device.limit !== null && device.limit.on
                onToggled: nextChecked => BatteryLimit.setEnabled(device.modelData.nativePath, nextChecked)
            }
            HintText {
                visible: _limitRow.visible && BatteryLimit.lastError.length > 0
                    && BatteryLimit.errorNative === device.modelData.nativePath
                text: BatteryLimit.lastError
                textColor: Theme.menuTextWarning
            }
        }
    }
}
