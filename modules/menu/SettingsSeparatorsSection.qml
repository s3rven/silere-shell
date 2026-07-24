import QtQuick
import "../../config"
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        ToggleRow {
            glyph: "󰡍"; label: "Compact spacing"
            description: "Separators between groups only"
            checked: ShellSettings.barCompact
            onToggled: ShellSettings.barCompact = !ShellSettings.barCompact
        }
        ToggleRow {
            glyph: "󰁌"; label: "Auto tighten"
            description: "Tightens spacing when widgets crowd the bar"
            checked: ShellSettings.barAutoCompact
            onToggled: ShellSettings.barAutoCompact = !ShellSettings.barAutoCompact
        }
        SelectRow {
            glyph: "󰻂"; label: "Separator"
            description: "Symbol shown between widget groups"
            currentValue: ShellSettings.dotStyle
            model: [
                { value: "·",     label: "Dot ·"     },
                { value: "•",     label: "Bullet •"  },
                { value: "◦",     label: "Ring ◦"    },
                { value: "|",     label: "Pipe |"    },
                { value: "slash", label: "Slash /"   },
                { value: "line",  label: "Line │"    },
                { value: "none",  label: "None"      }
            ]
            onChosen: (v) => ShellSettings.dotStyle = v
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
        CollapsibleSection {
            indent: 8
            expanded: ShellSettings.dotStyle !== "none"
            SliderRow {
                glyph: ShellSettings.dotTextGlyph
                glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.dotOpacity))
                label: "Separator opacity"
                value: ShellSettings.dotOpacity
                min: 0.10; max: 1.0; step: 0.05
                displayValue: Math.round(ShellSettings.dotOpacity * 100) + "%"
                onChanged: (v) => ShellSettings.dotOpacity = v
            }
        }
    }
}
