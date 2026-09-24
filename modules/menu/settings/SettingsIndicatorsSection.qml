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
                description: "Show it beside or instead of the title"
                key: "showWindowTitleApp"
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
                key: "networkSpeedInline"
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

    SectionLabel { label: "HOVER" }
    SettingsCard {
        ToggleRow {
            glyph: "󰍽"; label: "Hover highlight"
            key: "barHoverHighlight"
        }
        ToggleRow {
            glyph: "󰈈"; label: "Reveal values on hover"
            key: "valuesOnHover"
        }
        CollapsibleSection {
            expanded: ShellSettings.valuesOnHover
            ToggleRow {
                glyph: "󰡵"; label: "Level bars"
                checked: ShellSettings.hoverLevelBar
                description: "A slim bar while the value is hidden"
                onToggled: nextChecked => ShellSettings.hoverLevelBar = nextChecked
            }
        }
    }
}
