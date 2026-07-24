import QtQuick
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "NOW PLAYING"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰎇"; label: "Show artist + title"
            checked: ShellSettings.mediaWidgetFormat === "artist-title"
            onToggled: ShellSettings.mediaWidgetFormat = (ShellSettings.mediaWidgetFormat === "artist-title" ? "title" : "artist-title")
        }
        ToggleRow {
            glyph: "󰐊"; label: "Playback helper"
            description: "Play state and progress in the bar"
            checked: ShellSettings.mediaWidgetHelper
            onToggled: ShellSettings.mediaWidgetHelper = !ShellSettings.mediaWidgetHelper
        }
    }

    SectionLabel { label: "VISUALIZER" }
    SettingsCard {
        ToggleRow {
            glyph: "󰱐"; label: "Audio visualizer"
            description: "Runs only while audio is playing"
            checked: ShellSettings.mediaProgress
            onToggled: ShellSettings.mediaProgress = !ShellSettings.mediaProgress
            available: !SystemTools.ready || SystemTools.hasCava
            dependsNote: SystemTools.ready ? "cava missing" : "Checking"
        }
        CollapsibleSection {
            indent: 8
            expanded: ShellSettings.mediaProgress && SystemTools.hasCava
            ChoiceChipRow {
                glyph: "󰝚"; label: "Position"
                currentValue: ShellSettings.mediaVisualizerPosition
                model: [
                    { value: "media",  label: "Media" },
                    { value: "center", label: "Center" }
                ]
                onChosen: (v) => ShellSettings.mediaVisualizerPosition = v
            }
            ChoiceChipRow {
                glyph: "󰝚"; label: "Shape"
                currentValue: ShellSettings.mediaVisualizerStyle
                model: [
                    { value: "wave",  label: "Wave" },
                    { value: "bars",  label: "Bars" },
                    { value: "pulse", label: "Pulse" }
                ]
                onChosen: (v) => ShellSettings.mediaVisualizerStyle = v
            }
            ChoiceChipRow {
                glyph: "󰓅"; label: "Preset"
                currentValue: ShellSettings.mediaVisualizerPreset
                model: [
                    { value: "eco",      label: "Eco" },
                    { value: "balanced", label: "Balanced" },
                    { value: "smooth",   label: "Smooth" }
                ]
                onChosen: (v) => ShellSettings.mediaVisualizerPreset = v
            }
            HintText { text: "Preset sets bar count and framerate — Eco costs the least CPU." }
        }
    }
}
