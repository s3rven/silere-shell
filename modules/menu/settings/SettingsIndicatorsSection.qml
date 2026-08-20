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
            key: "showWindowTitle"
        }
        CollapsibleSection {
            expanded: ShellSettings.showWindowTitle
            ToggleRow {
                glyph: "󰀻"; label: "App name"
                key: "showWindowTitleApp"
            }
        }
        // the centre visualiser takes this anchor too, with or without a title to place
        CollapsibleSection {
            expanded: ShellSettings.showWindowTitle
                || (ShellSettings.mediaProgress && ShellSettings.mediaVisualizerPosition === "center")
            ToggleRow {
                glyph: "󰉠"; label: "Center between widgets"
                key: "windowTitleCenterGap"
            }
        }
    }

    SectionLabel { label: "INTERACTION" }
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
                glyph: "󰡵"; label: "Compact level bars"
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
            glyph: "󱟢"; label: "Hide charged battery"
            key: "batteryAutoHide"
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
}
