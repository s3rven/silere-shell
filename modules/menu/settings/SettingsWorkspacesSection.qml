import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "LAYOUT"; first: true }
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
    }

    SectionLabel { label: "CONTENT" }
    SettingsCard {
        ToggleRow {
            glyph: "󰎠"; label: "Numbers"
            key: "wsShowNumbers"
        }
        ToggleRow {
            glyph: "󰀻"; label: "App icons"
            description: "Up to three apps per workspace"
            key: "wsShowAppIcons"
        }
    }

    SectionLabel { label: "INTERACTION" }
    SettingsCard {
        ToggleRow {
            glyph: "󱕒"; label: "Scroll to switch"
            key: "wsScrollSwitch"
        }
    }

    SectionLabel { label: "MOTION" }
    SettingsCard {
        ToggleRow {
            glyph: "󰗘"; label: "Switch animation"
            key: "workspaceShift"
        }
        ToggleRow {
            glyph: "󰂟"; label: "Notification pulse"
            description: "Animate the workspace a notification came from"
            key: "wsNotifPulse"
        }
        ToggleRow {
            glyph: "󰕦"; label: "Urgent window pulse"
            description: "Animate a workspace demanding attention"
            key: "wsUrgentPulse"
        }
        HintText {
            visible: ShellSettings.reduceMotion
            text: "Reduce motion is on, so these animations stay off."
        }
    }
}
