import QtQuick
import "../../../services"
import "../../common"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    Component {
        id: _dividerPreview
        BarDivider {
            compact: false
            hasNext: true
            marked: true
            styleOverride: parent && parent.optionValue !== undefined
                ? String(parent.optionValue) : ""
        }
    }

    SectionLabel { label: "GAPS"; first: true }
    SettingsCard {
        // a divider spans twice the gap, so anything past 12 left whole widgets of empty bar
        ChoiceChipRow {
            key: "barSpacing"
            glyph: "󰤼"; label: "Widget gap"
            model: [
                { value: 4,  label: "Tight"  },
                { value: 8,  label: "Normal" },
                { value: 12, label: "Wide"   }
            ]
        }
        ToggleRow {
            glyph: "󰡍"; label: "Compact widgets"
            key: "barCompact"
        }
        CollapsibleSection {
            expanded: !ShellSettings.barCompact
            ToggleRow {
                glyph: "󰡌"; label: "Auto tighten"
                description: "Compact widgets only when the bar is full"
                key: "barAutoCompact"
            }
        }
        ToggleRow {
            glyph: "󰉠"; label: "Center between widgets"
            key: "barCenterInGap"
        }
    }

    SectionLabel { label: "DIVIDERS" }
    SettingsCard {
        SelectRow {
            key: "dotStyle"
            label: "Style"
            optionPreview: _dividerPreview
            model: [
                { value: "line",  label: "Line"       },
                { value: "|",     label: "Short line" },
                { value: "·",     label: "Dot"       },
                { value: "•",     label: "Bullet"    },
                { value: "◦",     label: "Ring"      },
                { value: "slash", label: "Slash"     },
                { value: "none",  label: "None"      }
            ]
        }
        CollapsibleSection {
            expanded: ShellSettings.dotStyle !== "none"
            ChoiceChipRow {
                key: "barSeparatorMode"
                glyph: "󰕯"; label: "Placement"
                model: [
                    { value: "groups",  label: "Groups" },
                    { value: "widgets", label: "Every"  }
                ]
            }
        }
    }
}
