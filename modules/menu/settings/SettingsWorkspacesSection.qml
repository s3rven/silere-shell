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
            value: ShellSettings.wsMinVisible
            min: 1; max: 10; step: 1
            displayValue: ShellSettings.wsMinVisible
            onChanged: (v) => ShellSettings.wsMinVisible = v
        }
        ToggleRow {
            glyph: "󰗘"; label: "Switch animation"
            checked: ShellSettings.workspaceShift
            onToggled: nextChecked => ShellSettings.workspaceShift = nextChecked
        }
        ToggleRow {
            glyph: "󱕒"; label: "Scroll to switch"
            checked: ShellSettings.wsScrollSwitch
            onToggled: nextChecked => ShellSettings.wsScrollSwitch = nextChecked
        }
        ToggleRow {
            glyph: "󰂟"; label: "Notification pulse"
            checked: ShellSettings.wsNotifPulse
            onToggled: nextChecked => ShellSettings.wsNotifPulse = nextChecked
        }
    }

    SectionLabel { label: "CONTENT" }
    SettingsCard {
        ChoiceChipRow {
            glyph: "◆"; label: "Active marker"
            currentValue: ShellSettings.wsActiveMarker
            model: [
                { value: "gem", label: "Gem" },
                { value: "dot", label: "Dot" },
                { value: "bar", label: "Bar" }
            ]
            onChosen: (v) => ShellSettings.wsActiveMarker = v
        }
        ToggleRow {
            glyph: "󰎠"; label: "Numbers"
            checked: ShellSettings.wsShowNumbers
            onToggled: nextChecked => ShellSettings.wsShowNumbers = nextChecked
        }
        SliderRow {
            glyph: ShellSettings.wsShowNumbers ? "1" : "•"
            glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.wsMarkerOpacity))
            label: "Marker opacity"
            value: ShellSettings.wsMarkerOpacity
            min: 0.2; max: 1.0; step: 0.05
            displayValue: Math.round(ShellSettings.wsMarkerOpacity * 100) + "%"
            onChanged: (v) => ShellSettings.wsMarkerOpacity = v
        }
        ToggleRow {
            glyph: "󰀻"; label: "App icons"
            description: "Show up to three running apps on occupied workspaces"
            checked: ShellSettings.wsShowAppIcons
            onToggled: nextChecked => ShellSettings.wsShowAppIcons = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.wsShowAppIcons
            ToggleRow {
                glyph: "󰹑"; label: "Monochrome icons"
                checked: ShellSettings.wsIconMono
                onToggled: nextChecked => ShellSettings.wsIconMono = nextChecked
            }
            SliderRow {
                glyph: "󰋩"; label: "Icon opacity"
                value: ShellSettings.wsIconOpacity
                min: 0.3; max: 1.0; step: 0.05
                displayValue: Math.round(ShellSettings.wsIconOpacity * 100) + "%"
                onChanged: (v) => ShellSettings.wsIconOpacity = v
            }
        }
    }
}
