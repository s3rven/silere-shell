import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "CONTENT"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰦩"; label: "Window title"
            checked: ShellSettings.showWindowTitle
            onToggled: nextChecked => ShellSettings.showWindowTitle = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.showWindowTitle
            ToggleRow {
                glyph: "󰀻"; label: "App name"
                checked: ShellSettings.showWindowTitleApp
                onToggled: nextChecked => ShellSettings.showWindowTitleApp = nextChecked
            }
            ToggleRow {
                glyph: "󰉞"; label: "Center between widgets"
                checked: ShellSettings.windowTitleCenterGap
                onToggled: nextChecked => ShellSettings.windowTitleCenterGap = nextChecked
            }
        }
    }

    SectionLabel { label: "INTERACTION" }
    SettingsCard {
        ToggleRow {
            glyph: "󰍽"; label: "Hover highlight"
            checked: ShellSettings.barHoverHighlight
            onToggled: nextChecked => ShellSettings.barHoverHighlight = nextChecked
        }
        ToggleRow {
            glyph: "󰈈"; label: "Reveal values on hover"
            checked: ShellSettings.valuesOnHover
            onToggled: nextChecked => ShellSettings.valuesOnHover = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.valuesOnHover
            ToggleRow {
                glyph: "󰦣"; label: "Compact level bars"
                checked: ShellSettings.hoverLevelBar
                description: "Keep levels visible"
                onToggled: nextChecked => ShellSettings.hoverLevelBar = nextChecked
            }
        }
    }

    SectionLabel { label: "BATTERY"; visible: Battery.available }
    SettingsCard {
        visible: Battery.available
        ToggleRow {
            glyph: "󰂃"; label: "Hide charged battery"
            checked: ShellSettings.batteryAutoHide
            onToggled: nextChecked => ShellSettings.batteryAutoHide = nextChecked
        }
    }

    SectionLabel { label: "NETWORK" }
    SettingsCard {
        ToggleRow {
            glyph: "󰓅"; label: "Network speed"
            checked: ShellSettings.networkTrafficStats
            available: Network.toolAvailable
            dependsNote: "No NetworkManager"
            onToggled: nextChecked => ShellSettings.networkTrafficStats = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.networkTrafficStats && Network.toolAvailable
            ToggleRow {
                glyph: "󰐃"; label: "Always show speed"
                checked: ShellSettings.networkSpeedInline
                onToggled: nextChecked => ShellSettings.networkSpeedInline = nextChecked
            }
        }
        ToggleRow {
            glyph: "󰦝"; label: "Connection beside VPN"
            checked: ShellSettings.netVpnShowLink
            available: Network.toolAvailable
            dependsNote: "No NetworkManager"
            onToggled: nextChecked => ShellSettings.netVpnShowLink = nextChecked
        }
    }
}
