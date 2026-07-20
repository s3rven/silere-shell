import QtQuick
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        ToggleRow {
            glyph: "󱀅"; label: "Show OSD"
            checked: ShellSettings.osdEnabled
            onToggled: ShellSettings.osdEnabled = !ShellSettings.osdEnabled
        }
        CollapsibleSection {
            expanded: ShellSettings.osdEnabled
            // Mode: floating pill vs bar-inline. Drives which sub-options apply.
            ToggleRow {
                glyph: "󰀱"; label: "Show in bar"
                description: "Volume and brightness in the bar center"
                checked: ShellSettings.osdBarIntegrated
                onToggled: ShellSettings.osdBarIntegrated = !ShellSettings.osdBarIntegrated
            }
            CollapsibleSection {
                expanded: !ShellSettings.osdBarIntegrated
                ToggleRow {
                    glyph: "󰖲"; label: "Match bar shape"
                    checked: ShellSettings.osdMatchBar
                    onToggled: ShellSettings.osdMatchBar = !ShellSettings.osdMatchBar
                }
            }
            ChoiceChipRow {
                glyph: "󰔛"; label: "Dismiss after"
                currentValue: ShellSettings.osdTimeout
                model: [
                    { value: 1000, label: "1s" },
                    { value: 2000, label: "2s" },
                    { value: 3000, label: "3s" },
                    { value: 5000, label: "5s" }
                ]
                onChosen: (v) => ShellSettings.osdTimeout = v
            }
            ChoiceChipRow {
                glyph: "󰒓"; label: "Show for"
                currentValue: ShellSettings.osdKindFilter
                model: [
                    { value: "both",       glyph: "󰓎", label: "Both" },
                    { value: "volume",     glyph: "󰕾", label: "Vol"  },
                    { value: "brightness", glyph: "󰃟", label: "Brt"  }
                ]
                onChosen: (v) => ShellSettings.osdKindFilter = v
            }
            ToggleRow {
                glyph: "󰓎"; label: "Volume emphasis"
                description: "Warm tint as volume nears max"
                checked: ShellSettings.osdVolumeTint
                onToggled: ShellSettings.osdVolumeTint = !ShellSettings.osdVolumeTint
            }
        }
    }
}
