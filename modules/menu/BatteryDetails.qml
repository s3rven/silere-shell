pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "controls"

Column {
    id: root

    width: parent ? parent.width : 0
    property var readings: Battery.details

    Repeater {
        model: root.readings

        Column {
            id: device
            required property var modelData
            width: root.width

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
        }
    }
}
