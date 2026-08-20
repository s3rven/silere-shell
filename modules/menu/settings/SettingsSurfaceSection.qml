import QtQuick
import "../../../config"
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
        // not under the floating gate: widget hover capsules and the OSD pill take this
        // radius while docked, where the bar's own corners are multiplied away
        SliderRow {
            glyph: "󱓻"; label: "Roundness"
            key: "barRadius"
            // the bar caps its corners at half its height; the raw number overstates past that
            displayValue: ShellSettings.barRadius === 0 ? "Flat"
                : ShellSettings.barRadius >= ShellSettings.barHeight / 2 ? "Round"
                : ShellSettings.barRadius + "px"
        }
        SliderRow {
            glyph: "󰗌"; label: "Opacity"
            key: "barOpacity"
            step: 0.02
            displayValue: Math.round(Theme.panelOpacity * 100) + "%"
        }
        ToggleRow {
            glyph: "󱡓"; label: "Popups match bar opacity"
            description: "Notifications, calendar, tray and quick actions"
            key: "popupMatchBarOpacity"
        }
    }

    SectionLabel { label: "FLOATING" }
    SettingsCard {
        ToggleRow {
            glyph: "󰖲"; label: "Floating bar"
            key: "barFloating"
        }
        // one disclosure for one toggle: two gated on the same flag played two reveals
        CollapsibleSection {
            expanded: ShellSettings.barFloating
            SliderRow {
                glyph: "󰡎"; label: "Width"
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
    }
}
