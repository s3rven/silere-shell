import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "LAYOUT"; first: true }
    SettingsCard {
        SliderRow {
            glyph: "󰕰"; label: "Visible"
            key: "wsMinVisible"
            displayValue: ShellSettings.wsMinVisible
        }
        ChoiceChipRow {
            glyph: ShellSettings.wsActiveMarker === "bar" ? "━"
                : ShellSettings.wsActiveMarker === "dot" ? "●" : "◆"
            label: "Active marker"
            currentValue: ShellSettings.wsActiveMarker
            model: [
                { value: "gem", label: "Gem" },
                { value: "dot", label: "Dot" },
                { value: "bar", label: "Line" }
            ]
            onChosen: (v) => ShellSettings.wsActiveMarker = v
        }
    }

    SectionLabel { label: "CONTENT" }
    SettingsCard {
        ToggleRow {
            glyph: "󰎠"; label: "Numbers"
            key: "wsShowNumbers"
        }
        SliderRow {
            glyph: ShellSettings.wsShowNumbers ? "1" : "•"
            glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.wsMarkerOpacity))
            label: ShellSettings.wsShowNumbers ? "Number opacity" : "Dot opacity"
            key: "wsMarkerOpacity"
            displayValue: Math.round(ShellSettings.wsMarkerOpacity * 100) + "%"
        }
        ToggleRow {
            glyph: "󰀻"; label: "App icons"
            description: "Up to three apps per workspace"
            key: "wsShowAppIcons"
        }
        CollapsibleSection {
            expanded: ShellSettings.wsShowAppIcons
            ToggleRow {
                glyph: "󰹑"; label: "Monochrome icons"
                key: "wsIconMono"
            }
            SliderRow {
                glyph: "󰋩"; label: "Icon opacity"
                key: "wsIconOpacity"
                displayValue: Math.round(ShellSettings.wsIconOpacity * 100) + "%"
            }
        }
    }

    SectionLabel { label: "BEHAVIOR" }
    SettingsCard {
        ToggleRow {
            glyph: "󱕒"; label: "Scroll to switch"
            key: "wsScrollSwitch"
        }
        ToggleRow {
            glyph: "󰗘"; label: "Switch animation"
            key: "workspaceShift"
        }
        ToggleRow {
            glyph: "󰂟"; label: "Notification pulse"
            key: "wsNotifPulse"
        }
        ToggleRow {
            glyph: "󰕦"; label: "Urgent window pulse"
            description: "Animate a workspace demanding attention"
            key: "wsUrgentPulse"
        }
    }
}
