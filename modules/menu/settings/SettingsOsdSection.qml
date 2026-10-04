import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

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
                    description: "Use the bar's height and roundness"
                    key: "osdMatchBar"
                }
            }
            SliderRow {
                glyph: "󰔛"; label: "Dismiss after"
                displayValue: (ShellSettings.osdTimeout / 1000) + "s"
                key: "osdTimeout"
                step: 500
            }
            ChoiceChipRow {
                key: "osdKindFilter"
                glyph: "󰈶"; label: "Feedback for"
                model: [
                    { value: "both",       label: "Both" },
                    { value: "volume",     label: "Volume" },
                    { value: "brightness", label: "Bright" }
                ]
            }
        }
    }
}
