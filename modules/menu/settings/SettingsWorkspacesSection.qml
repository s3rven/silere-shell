import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "APPEARANCE"; first: true }
    SettingsCard {
        SliderRow {
            glyph: "󰕰"; label: "Workspaces shown"
            key: "wsMinVisible"
            displayValue: ShellSettings.wsMinVisible
        }
        ChoiceChipRow {
            key: "wsActiveMarker"
            glyph: ShellSettings.wsActiveMarker === "bar" ? "━"
                : ShellSettings.wsActiveMarker === "dot" ? "●" : "◆"
            label: "Active marker"
            model: [
                { value: "gem", label: "Gem" },
                { value: "dot", label: "Dot" },
                { value: "bar", label: "Line" }
            ]
        }
        ToggleRow {
            glyph: "󰎠"; label: "Numbers"
            key: "wsShowNumbers"
        }
        ToggleRow {
            glyph: "󰀻"; label: "App icons"
            key: "wsShowAppIcons"
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
            key: "wsUrgentPulse"
        }
    }
}
