import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "NOW PLAYING"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰎇"; label: "Artist and title"
            checked: ShellSettings.mediaWidgetFormat === "artist-title"
            onToggled: nextChecked => ShellSettings.mediaWidgetFormat =
                nextChecked ? "artist-title" : "title"
        }
        ChoiceChipRow {
            glyph: "󰘖"; label: "Track text width"
            // a size implies the reserved slot, which is what escapes the dynamic budget clamp
            currentValue: ShellSettings.mediaWidgetFixedWidth
                ? ShellSettings.mediaWidgetMaxWidth : 0
            model: [
                { value: 0,   label: "Auto" },
                { value: 120, label: "Short" },
                { value: 160, label: "Normal" },
                { value: 200, label: "Wide" }
            ]
            onChosen: (v) => {
                if (v === 0) {
                    ShellSettings.mediaWidgetFixedWidth = false
                    return
                }
                ShellSettings.mediaWidgetMaxWidth = v
                ShellSettings.mediaWidgetFixedWidth = true
            }
        }
        ToggleRow {
            glyph: "󰐊"; label: "Playback status"
            description: "Show play state and progress"
            checked: ShellSettings.mediaWidgetHelper
            onToggled: nextChecked => ShellSettings.mediaWidgetHelper = nextChecked
        }
    }

    SectionLabel { label: "VISUALIZER" }
    SettingsCard {
        ToggleRow {
            glyph: "󰱐"; label: "Audio visualizer"
            description: "Active during playback"
            checked: ShellSettings.mediaProgress
            onToggled: nextChecked => ShellSettings.mediaProgress = nextChecked
            available: !SystemTools.ready || SystemTools.hasCava
            dependsNote: SystemTools.ready ? "No cava" : "Checking"
        }
        CollapsibleSection {
            expanded: ShellSettings.mediaProgress && SystemTools.hasCava
            ChoiceChipRow {
                glyph: "󰍹"; label: "Position"
                currentValue: ShellSettings.mediaVisualizerPosition
                model: [
                    { value: "media",  label: "Media" },
                    { value: "center", label: "Center" }
                ]
                onChosen: (v) => ShellSettings.mediaVisualizerPosition = v
            }
            ChoiceChipRow {
                glyph: "󰀁"; label: "Shape"
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
            HintText { text: "Eco uses the least CPU." }
        }
    }
}
