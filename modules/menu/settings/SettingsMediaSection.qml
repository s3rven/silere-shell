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
        ToggleRow {
            glyph: "󰐊"; label: "Playback status"
            description: "Show play state and progress"
            key: "mediaWidgetHelper"
        }
        ToggleRow {
            glyph: "󰥶"; label: "Cover art from the web"
            description: "Fetches art the player links to"
            key: "mediaRemoteArt"
        }
    }

    SectionLabel { label: "VISUALIZER" }
    SettingsCard {
        ToggleRow {
            glyph: "󰱐"; label: "Audio visualizer"
            description: ShellSettings.reduceMotion ? "Paused by Reduce motion"
                : "Active during playback"
            key: "mediaProgress"
            available: !SystemTools.ready || Media.cavaAvailable
            dependsNote: !SystemTools.ready ? "Checking"
                : !SystemTools.hasCava ? "No cava" : "Runtime unavailable"
        }
        CollapsibleSection {
            expanded: ShellSettings.mediaProgress && Media.cavaAvailable
            ChoiceChipRow {
                glyph: "󰍹"; label: "Position"
                currentValue: ShellSettings.mediaVisualizerPosition
                model: [
                    { value: "media",     label: "Media" },
                    { value: "center",    label: "Center" },
                    { value: "underline", label: "Underline" }
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
            SliderRow {
                glyph: "󰗌"; label: "Opacity"
                key: "mediaVisualizerOpacity"
                step: 0.05
                displayValue: Math.round(ShellSettings.mediaVisualizerOpacity * 100) + "%"
            }
            // the preset names say nothing about what they cost; the shape changes both
            HintText { text: Media.visualizerLabel + ". Eco uses the least CPU." }
            CollapsibleSection {
                expanded: ShellSettings.reduceMotion
                HintText {
                    text: "Reduce motion is on, so the visualizer stays off."
                }
            }
        }
    }
}
