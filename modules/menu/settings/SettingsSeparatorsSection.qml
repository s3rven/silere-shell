import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "LAYOUT"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰡍"; label: "Compact spacing"
            description: "Reduce widget padding and gaps"
            checked: ShellSettings.barCompact
            onToggled: nextChecked => ShellSettings.barCompact = nextChecked
        }
        CollapsibleSection {
            expanded: !ShellSettings.barCompact
            ToggleRow {
                glyph: "󰁌"; label: "Auto tighten"
                description: "Tighten when widgets crowd the bar"
                checked: ShellSettings.barAutoCompact
                onToggled: nextChecked => ShellSettings.barAutoCompact = nextChecked
            }
        }
        ChoiceChipRow {
            glyph: "󰤼"; label: "Spacing"
            currentValue: ShellSettings.barSpacing
            model: [
                { value: 8,  label: "Tight"  },
                { value: 11, label: "Normal" },
                { value: 15, label: "Loose"  }
            ]
            onChosen: (v) => ShellSettings.barSpacing = v
        }
    }

    SectionLabel { label: "DIVIDERS" }
    SettingsCard {
        SelectRow {
            glyph: ShellSettings.dotTextGlyph; label: "Style"
            description: "Divider between widgets"
            currentValue: ShellSettings.dotStyle
            model: [
                { value: "line",  label: "Line"       },
                { value: "|",     label: "Short line" },
                { value: "·",     label: "Dot"       },
                { value: "•",     label: "Bullet"    },
                { value: "◦",     label: "Ring"      },
                { value: "slash", label: "Slash"     },
                { value: "none",  label: "None"      }
            ]
            onChosen: (v) => ShellSettings.dotStyle = v
        }
        CollapsibleSection {
            expanded: ShellSettings.dotStyle !== "none"
            ChoiceChipRow {
                glyph: "󰕯"; label: "Placement"
                currentValue: ShellSettings.barSeparatorMode
                model: [
                    { value: "groups",  label: "Groups" },
                    { value: "widgets", label: "Every"  }
                ]
                onChosen: (v) => ShellSettings.barSeparatorMode = v
            }
            SliderRow {
                glyph: ShellSettings.dotTextGlyph
                glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.dotOpacity))
                label: "Opacity"
                value: ShellSettings.dotOpacity
                min: 0.10; max: 1.0; step: 0.05
                displayValue: Math.round(ShellSettings.dotOpacity * 100) + "%"
                onChanged: (v) => ShellSettings.dotOpacity = v
            }
        }
    }
}
