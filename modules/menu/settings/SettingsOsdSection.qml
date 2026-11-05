import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "APPEARANCE"; first: true }

    SettingsCard {
        ToggleRow {
            glyph: "󱀅"; label: "On-screen display"
            key: "osdEnabled"
        }
        CollapsibleSection {
            expanded: ShellSettings.osdEnabled
            ToggleRow {
                glyph: "󰀱"; label: "Show in bar"
                key: "osdBarIntegrated"
            }
            CollapsibleSection {
                expanded: !ShellSettings.osdBarIntegrated
                ToggleRow {
                    glyph: "󰖲"; label: "Match bar shape"
                    key: "osdMatchBar"
                }
            }
            SliderRow {
                glyph: "󰔛"; label: "Dismiss after"
                displayValue: (ShellSettings.osdTimeout / 1000) + "s"
                key: "osdTimeout"
                step: 500
            }
        }
    }
}
