import QtQuick
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "CONTENT"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰦩"; label: "Window title"
            checked: ShellSettings.showWindowTitle
            onToggled: ShellSettings.showWindowTitle = !ShellSettings.showWindowTitle
        }
        CollapsibleSection {
            expanded: ShellSettings.showWindowTitle
            ToggleRow {
                glyph: "󰀻"; label: "App name"
                checked: ShellSettings.showWindowTitleApp
                onToggled: ShellSettings.showWindowTitleApp = !ShellSettings.showWindowTitleApp
            }
            ToggleRow {
                glyph: "󰉞"; label: "Center between widgets"
                checked: ShellSettings.windowTitleCenterGap
                onToggled: ShellSettings.windowTitleCenterGap = !ShellSettings.windowTitleCenterGap
            }
        }
    }

    SectionLabel { label: "INTERACTION" }
    SettingsCard {
        ToggleRow {
            glyph: "󰍽"; label: "Hover highlight"
            checked: ShellSettings.barHoverHighlight
            onToggled: ShellSettings.barHoverHighlight = !ShellSettings.barHoverHighlight
        }
        ToggleRow {
            glyph: "󰈈"; label: "Reveal values on hover"
            description: "Battery, volume, brightness, and workspace numbers"
            checked: ShellSettings.valuesOnHover
            onToggled: ShellSettings.valuesOnHover = !ShellSettings.valuesOnHover
        }
        CollapsibleSection {
            expanded: ShellSettings.valuesOnHover
            ToggleRow {
                glyph: "󰦣"; label: "Compact level bars"
                checked: ShellSettings.hoverLevelBar
                description: "Show battery, volume, and brightness levels before hover"
                onToggled: ShellSettings.hoverLevelBar = !ShellSettings.hoverLevelBar
            }
        }
    }

    SectionLabel { label: "STATUS WIDGETS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰂃"; label: "Hide charged battery"
            checked: ShellSettings.batteryAutoHide
            available: Battery.available
            dependsNote: "No battery"
            onToggled: ShellSettings.batteryAutoHide = !ShellSettings.batteryAutoHide
        }
        ToggleRow {
            glyph: "󰓅"; label: "Network speed"
            checked: ShellSettings.networkTrafficStats
            available: Network.toolAvailable
            dependsNote: "NetworkManager missing"
            onToggled: ShellSettings.networkTrafficStats = !ShellSettings.networkTrafficStats
        }
        CollapsibleSection {
            expanded: ShellSettings.networkTrafficStats
            ToggleRow {
                glyph: "󰐃"; label: "Always show speed"
                checked: ShellSettings.networkSpeedInline
                onToggled: ShellSettings.networkSpeedInline = !ShellSettings.networkSpeedInline
            }
        }
        ToggleRow {
            glyph: "󰦝"; label: "Connection under VPN"
            checked: ShellSettings.netVpnShowLink
            available: Network.toolAvailable
            dependsNote: "NetworkManager missing"
            onToggled: ShellSettings.netVpnShowLink = !ShellSettings.netVpnShowLink
        }
    }
}
