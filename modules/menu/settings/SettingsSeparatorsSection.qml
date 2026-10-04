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
        SliderRow {
            glyph: "󰤼"; label: "Widget gap"
            key: "barSpacing"
            displayValue: ShellSettings.barSpacing + "px"
        }
        ToggleRow {
            glyph: "󰡍"; label: "Compact widgets"
            description: "Reduce widget padding and gaps"
            key: "barCompact"
        }
        CollapsibleSection {
            expanded: !ShellSettings.barCompact
            ToggleRow {
                glyph: "󰡌"; label: "Auto tighten"
                description: "Tighten when widgets crowd the bar"
                key: "barAutoCompact"
            }
        }
        ToggleRow {
            glyph: "󰉠"; label: "Center between widgets"
            description: "Balance the middle zone between both sides"
            key: "barCenterInGap"
        }
    }

    SectionLabel { label: "DIVIDERS" }
    SettingsCard {
        SelectRow {
            key: "dotStyle"
            label: "Style"
            description: "Divider between widgets"
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
