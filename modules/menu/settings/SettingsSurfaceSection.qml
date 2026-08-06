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
            value: ShellSettings.barOpacity
            min: 0.4; max: 1.0; step: 0.02
            displayValue: Math.round(ShellSettings.barOpacity * 100) + "%"
            onChanged: (v) => ShellSettings.barOpacity = v
        }
        // not under FLOATING: widget hover capsules and the OSD pill borrow this rounding
        // while the bar is docked too, so it has to stay reachable
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
            expanded: ShellSettings.barCornerStyle === "round"
            SliderRow {
                glyph: "󱓻"; label: "Roundness"
                value: ShellSettings.barRadius
                min: 2; max: 28; step: 1
                displayValue: ShellSettings.barRadius + "px"
                onChanged: (v) => ShellSettings.barRadius = Math.round(v)
            }
        }
    }

    SectionLabel { label: "FLOATING" }
    SettingsCard {
        ToggleRow {
            glyph: "󰖲"; label: "Floating bar"
            checked: ShellSettings.barFloating
            onToggled: nextChecked => ShellSettings.barFloating = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.barFloating
            SliderRow {
                glyph: "󰁌"; label: "Width"
                value: ShellSettings.barWidth
                min: 0.5; max: 1.0; step: 0.02
                displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
                onChanged: (v) => ShellSettings.barWidth = v
            }
        }
    }

    SectionLabel { label: "SHADOWS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰘷"; label: "Shell shadows"
            description: "Popups, notifications and the OSD; the bar casts one only while floating"
            checked: ShellSettings.barShadow
            onToggled: nextChecked => ShellSettings.barShadow = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.barShadow
            SliderRow {
                glyph: "󰘷"; label: "Shadow depth"
                value: ShellSettings.barShadowStrength
                min: 0.3; max: 2.0; step: 0.1
                displayValue: Math.round(ShellSettings.barShadowStrength * 100) + "%"
                onChanged: (v) => ShellSettings.barShadowStrength = v
            }
        }
    }
}
