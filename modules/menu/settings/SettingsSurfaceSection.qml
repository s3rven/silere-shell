import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "BAR"; first: true }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰍹"; label: "Position"
            currentValue: ShellSettings.barPosition
            model: [
                { value: "top",    label: "Top"    },
                { value: "bottom", label: "Bottom" }
            ]
            onChosen: (v) => ShellSettings.barPosition = v
        }
        ChoiceChipRow {
            glyph: "󰲏"; label: "Height"
            currentValue: ShellSettings.barHeight
            model: [
                { value: 28, label: "Compact" },
                { value: 36, label: "Normal"  },
                { value: 44, label: "Tall"    }
            ]
            onChosen: (v) => ShellSettings.barHeight = v
        }
        SliderRow {
            glyph: "󰗌"; label: "Opacity"
            key: "barOpacity"
            step: 0.02
            displayValue: Math.round(ShellSettings.barOpacity * 100) + "%"
        }
    }

    SectionLabel { label: "FLOATING" }
    SettingsCard {
        ToggleRow {
            glyph: "󰖲"; label: "Floating bar"
            key: "barFloating"
        }
        CollapsibleSection {
            expanded: ShellSettings.barFloating
            SliderRow {
                glyph: "󰁌"; label: "Width"
                key: "barWidth"
                step: 0.02
                displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
            }
            // stepped in 4s: the bar edge has to stay on the 4px grid or hairlines straddle a physical pixel
            SliderRow {
                glyph: "󰡏"; label: "Edge gap"
                key: "barGap"
                step: 4
                displayValue: ShellSettings.barGap === 0 ? "None" : ShellSettings.barGap + "px"
            }
        }
        // only the floating bar paints its own corners; docked multiplies the radius by 0
        CollapsibleSection {
            expanded: ShellSettings.barFloating
            SliderRow {
                glyph: "󱓻"; label: "Roundness"
                key: "barRadius"
                displayValue: ShellSettings.barRadius === 0 ? "Flat" : ShellSettings.barRadius + "px"
            }
        }
    }

    SectionLabel { label: "SHADOWS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰘷"; label: "Shell shadows"
            description: "Popups, notifications, OSD, and floating bar"
            key: "barShadow"
        }
        CollapsibleSection {
            expanded: ShellSettings.barShadow
            SliderRow {
                glyph: "󰘷"; label: "Shadow depth"
                key: "barShadowStrength"
                step: 0.1
                displayValue: Math.round(ShellSettings.barShadowStrength * 100) + "%"
            }
        }
    }
}
