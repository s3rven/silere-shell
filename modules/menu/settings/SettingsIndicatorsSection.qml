import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0

    SectionLabel { label: "WINDOW TITLE"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰦩"; label: "Window title"
            key: "showWindowTitle"
        }
        CollapsibleSection {
            expanded: ShellSettings.showWindowTitle
            ToggleRow {
                glyph: "󰀻"; label: "App name"
                key: "showWindowTitleApp"
            }
            ToggleRow {
                glyph: "󰋩"; label: "App icon"
                key: "showWindowTitleIcon"
            }
        }
    }

    SectionLabel { label: "STATUS" }
    SettingsCard {
        ToggleRow {
            visible: Battery.available
            glyph: "󱟢"; label: "Hide while plugged in"
            key: "batteryAutoHide"
        }
        ToggleRow {
            key: "networkTrafficStats"
            glyph: "󰓅"; label: "Network speed"
            available: Network.toolAvailable
            dependsNote: "No NetworkManager"
        }
        CollapsibleSection {
            expanded: ShellSettings.networkTrafficStats && Network.toolAvailable
            ToggleRow {
                glyph: "󰐃"; label: "Always show speed"
                key: "networkSpeedInline"
            }
        }
        ToggleRow {
            key: "netVpnShowLink"
            glyph: "󰦝"; label: "Connection beside VPN"
            available: Network.toolAvailable
            dependsNote: "No NetworkManager"
        }
    }

    SectionLabel { label: "SYSTEM MONITOR" }
    SettingsCard {
        ToggleRow {
            glyph: "󰍛"; label: "System monitor"
            key: "barShowSystem"
            description: ShellSettings.barShowSystem && !SysInfo.monitorHasReadings
                ? "Choose a reading below to show it on the bar" : ""
        }
        CollapsibleSection {
            expanded: ShellSettings.barShowSystem
            ToggleRow {
                glyph: "󰍛"; label: "CPU usage"
                key: "systemShowCpu"
            }
            ToggleRow {
                glyph: "󰘚"; label: "Memory in use"
                key: "systemShowMemory"
            }
            ToggleRow {
                glyph: "󰔏"; label: "CPU temperature"
                key: "systemShowTemp"
                available: !CpuTemp.sensorMissing
                dependsNote: "No sensor"
            }
            ChoiceChipRow {
                glyph: "󰞯"; label: "Style"
                searchKey: "systemRings"
                currentValue: ShellSettings.systemRings ? "rings" : "plain"
                model: [
                    { value: "plain", label: "Plain" },
                    { value: "rings", label: "Rings" }
                ]
                onChosen: (v) => ShellSettings.systemRings = v === "rings"
            }
        }
    }
}
