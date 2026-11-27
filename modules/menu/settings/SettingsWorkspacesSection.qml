import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "APPEARANCE"; first: true }
    SettingsCard {
        SliderRow {
            glyph: "󰕰"; label: "Workspaces per page"
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
    }

    SectionLabel { label: "APP ICONS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰀻"; label: "Show app icons"
            key: "wsShowAppIcons"
            description: "Line shows icons on the active workspace"
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
            available: !ShellSettings.reduceMotion
            dependsNote: "Off with Reduce motion"
        }
        ToggleRow {
            glyph: "󰂟"; label: "Notification pulse"
            key: "wsNotifPulse"
            available: !ShellSettings.reduceMotion
            dependsNote: "Off with Reduce motion"
        }
        ToggleRow {
            glyph: "󰕦"; label: "Urgent window pulse"
            key: "wsUrgentPulse"
        }
    }
}
