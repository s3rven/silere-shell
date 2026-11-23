import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

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
            glyph: "󱟢"; label: "Hide charged battery"
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

    SectionLabel { label: "COMMAND" }
    SettingsCard {
        ToggleRow {
            glyph: "󰆍"; label: "Command"
            key: "barShowCustom"
            // a stopped script says why here; with no command there is nothing to report
            description: ShellSettings.barShowCustom && ShellSettings.customCommand.trim().length > 0
                && CustomCommand.lastError.length > 0 ? "Hidden: it " + CustomCommand.lastError
                : "A script's output on the bar"
        }
        CollapsibleSection {
            expanded: ShellSettings.barShowCustom
            CommandEditor {
                settingKey: "customCommand"
                label: "Command to run"
                example: "~/.local/bin/status --json"
                inputDescription: "Program and arguments, run without a shell"
                savedHint: "Saved. Plain lines or waybar's JSON both work."
                emptyHint: "A program and its arguments; empty hides the widget."
            }
            SelectRow {
                key: "customInterval"
                glyph: "󰔛"; label: "Every"
                fallbackLabel: ShellSettings.customInterval + " s"
                model: [
                    { value: 5, label: "5 seconds" },
                    { value: 30, label: "30 seconds" },
                    { value: 60, label: "1 minute" },
                    { value: 300, label: "5 minutes" },
                    { value: 900, label: "15 minutes" },
                    { value: 3600, label: "1 hour" }
                ]
            }
            CommandEditor {
                settingKey: "customClickCommand"
                label: "On click"
                example: "pavucontrol"
                savedHint: "Saved. Runs when you click the widget."
                emptyHint: "Empty: a click runs the command again."
            }
        }
    }
}
