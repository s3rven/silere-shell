import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "GENERAL"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󱀅"; label: "On-screen display"
            checked: ShellSettings.osdEnabled
            onToggled: nextChecked => ShellSettings.osdEnabled = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.osdEnabled
            ToggleRow {
                glyph: "󰀱"; label: "Show in bar"
                description: "Use bar center instead of a popup"
                checked: ShellSettings.osdBarIntegrated
                onToggled: nextChecked => ShellSettings.osdBarIntegrated = nextChecked
            }
            CollapsibleSection {
                expanded: !ShellSettings.osdBarIntegrated
                ToggleRow {
                    glyph: "󰖲"; label: "Match bar shape"
                    checked: ShellSettings.osdMatchBar
                    onToggled: nextChecked => ShellSettings.osdMatchBar = nextChecked
                }
            }
        }
    }

    CollapsibleSection {
        expanded: ShellSettings.osdEnabled

        SectionLabel { label: "FEEDBACK" }
        SettingsCard {
            SliderRow {
                glyph: "󰔛"; label: "Dismiss after"
                displayValue: (ShellSettings.osdTimeout / 1000) + "s"
                value: ShellSettings.osdTimeout
                min: 500; max: 10000; step: 500
                onChanged: (v) => ShellSettings.osdTimeout = v
            }
            ChoiceChipRow {
                glyph: "󰒓"; label: "Feedback for"
                currentValue: ShellSettings.osdKindFilter
                model: [
                    { value: "both",       glyph: "󰓎", label: "Both" },
                    { value: "volume",     glyph: "󰕾", label: "Vol"  },
                    { value: "brightness", glyph: "󰃟", label: "Brt"  }
                ]
                onChosen: (v) => ShellSettings.osdKindFilter = v
            }
            CollapsibleSection {
                expanded: ShellSettings.osdKindFilter !== "brightness"
                ToggleRow {
                    glyph: "󰓎"; label: "Volume emphasis"
                    description: "Warm tint near maximum"
                    checked: ShellSettings.osdVolumeTint
                    onToggled: nextChecked => ShellSettings.osdVolumeTint = nextChecked
                }
            }
        }
    }
}
