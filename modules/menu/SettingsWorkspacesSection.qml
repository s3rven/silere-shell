import QtQuick
import "../../config"
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "LAYOUT" }
    SettingsCard {
        SliderRow {
            glyph: "󰕰"; label: "Visible"
            value: ShellSettings.wsMinVisible
            min: 1; max: 10; step: 1
            displayValue: ShellSettings.wsMinVisible
            onChanged: (v) => ShellSettings.wsMinVisible = v
        }
        ToggleRow {
            glyph: "󰗘"; label: "Animated switch"
            checked: ShellSettings.workspaceShift
            onToggled: ShellSettings.workspaceShift = !ShellSettings.workspaceShift
        }
        ToggleRow {
            glyph: "󱕒"; label: "Scroll to switch"
            checked: ShellSettings.wsScrollSwitch
            onToggled: ShellSettings.wsScrollSwitch = !ShellSettings.wsScrollSwitch
        }
        ToggleRow {
            glyph: "󰂟"; label: "Notification pulse"
            checked: ShellSettings.wsNotifPulse
            onToggled: ShellSettings.wsNotifPulse = !ShellSettings.wsNotifPulse
        }
    }

    SectionLabel { label: "CONTENT" }
    SettingsCard {
        ChoiceChipRow {
            glyph: "◆"; label: "Active marker"
            currentValue: ShellSettings.wsActiveMarker
            model: [
                { value: "gem", label: "Gem" },
                { value: "dot", label: "Dot" }
            ]
            onChosen: (v) => ShellSettings.wsActiveMarker = v
        }
        ToggleRow {
            glyph: "󰎠"; label: "Numbers"
            checked: ShellSettings.wsShowNumbers
            onToggled: ShellSettings.wsShowNumbers = !ShellSettings.wsShowNumbers
        }
        CollapsibleSection {
            expanded: ShellSettings.wsShowNumbers
            ToggleRow {
                glyph: "󰮚"; label: "Roman numerals"
                checked: ShellSettings.wsRomanNumerals
                onToggled: ShellSettings.wsRomanNumerals = !ShellSettings.wsRomanNumerals
            }
        }
        SliderRow {
            glyph: ShellSettings.wsShowNumbers
                ? (ShellSettings.wsRomanNumerals ? "Ⅰ" : "1")
                : "•"
            glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.wsMarkerOpacity))
            label: "Marker opacity"
            value: ShellSettings.wsMarkerOpacity
            min: 0.2; max: 1.0; step: 0.05
            displayValue: Math.round(ShellSettings.wsMarkerOpacity * 100) + "%"
            onChanged: (v) => ShellSettings.wsMarkerOpacity = v
        }
        ToggleRow {
            glyph: "󰀻"; label: "App icons"; badge: "beta"
            description: "Show up to three running apps on occupied workspaces"
            checked: ShellSettings.wsShowAppIcons
            onToggled: ShellSettings.wsShowAppIcons = !ShellSettings.wsShowAppIcons
        }
        CollapsibleSection {
            expanded: ShellSettings.wsShowAppIcons
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
