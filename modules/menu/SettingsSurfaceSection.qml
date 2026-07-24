import QtQuick
import "../../services"

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
            value: ShellSettings.barOpacity
            min: 0.4; max: 1.0; step: 0.02
            displayValue: Math.round(ShellSettings.barOpacity * 100) + "%"
            onChanged: (v) => ShellSettings.barOpacity = v
        }
    }

    SectionLabel { label: "FLOATING" }
    SettingsCard {
        ToggleRow {
            glyph: "󰖲"; label: "Floating bar"
            checked: ShellSettings.barFloating
            onToggled: ShellSettings.barFloating = !ShellSettings.barFloating
        }
        CollapsibleSection {
            indent: 8
            expanded: ShellSettings.barFloating
            SliderRow {
                glyph: "󰁌"; label: "Width"
                value: ShellSettings.barWidth
                min: 0.5; max: 1.0; step: 0.02
                displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
                onChanged: (v) => ShellSettings.barWidth = v
            }
            ChoiceChipRow {
                glyph: "󰀁"; label: "Shape"
                currentValue: ShellSettings.barCornerStyle
                model: [
                    { value: "flat",  label: "Flat"  },
                    { value: "round", label: "Round" }
                ]
                onChosen: (v) => ShellSettings.barCornerStyle = v
            }
            CollapsibleSection {
                indent: 8
                expanded: ShellSettings.barCornerStyle === "round"
                SliderRow {
                    glyph: "󱓻"; label: "Roundness"
                    value: ShellSettings.barRadius
                    min: 2; max: 28; step: 1
                    displayValue: ShellSettings.barRadius + "px"
                    onChanged: (v) => ShellSettings.barRadius = Math.round(v)
                }
            }
            ToggleRow {
                glyph: "󰘷"; label: "Shell shadows"
                checked: ShellSettings.barShadow
                onToggled: ShellSettings.barShadow = !ShellSettings.barShadow
            }
            CollapsibleSection {
                indent: 8
                expanded: ShellSettings.barShadow
                SliderRow {
                    glyph: "󰔏"; label: "Shadow depth"
                    value: ShellSettings.barShadowStrength
                    min: 0.3; max: 2.0; step: 0.1
                    displayValue: Math.round(ShellSettings.barShadowStrength * 100) + "%"
                    onChanged: (v) => ShellSettings.barShadowStrength = v
                }
            }
        }
    }
}
