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
            key: "osdEnabled"
        }
        CollapsibleSection {
            expanded: ShellSettings.osdEnabled
            ToggleRow {
                glyph: "󰀱"; label: "Show in bar"
                description: "Use bar center instead of a popup"
                key: "osdBarIntegrated"
            }
            CollapsibleSection {
                expanded: !ShellSettings.osdBarIntegrated
                ToggleRow {
                    glyph: "󰖲"; label: "Match bar shape"
                    key: "osdMatchBar"
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
                key: "osdTimeout"
                step: 500
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
                    key: "osdVolumeTint"
                }
            }
        }
    }
}
