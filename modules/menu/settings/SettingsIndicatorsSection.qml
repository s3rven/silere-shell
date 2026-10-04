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
            description: "Show Wi-Fi or Ethernet while on VPN"
            available: Network.toolAvailable
            dependsNote: "No NetworkManager"
        }
    }
}
