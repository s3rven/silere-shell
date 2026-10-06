import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "NOW PLAYING"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰎇"; label: "Artist"
            description: "Shown before the track title"
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
            description: "Image hosts can see what you play"
            key: "mediaRemoteArt"
            available: !SystemTools.ready || Media.remoteArtAvailable
            dependsNote: "No curl"
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
                key: "mediaVisualizerPosition"
                glyph: "󰍹"; label: "Position"
                model: [
                    { value: "media",     label: "Media" },
                    { value: "center",    label: "Center" },
                    { value: "underline", label: "Underline" }
                ]
            }
            ChoiceChipRow {
                key: "mediaVisualizerStyle"
                glyph: "󰀁"; label: "Shape"
                model: [
                    { value: "wave",  label: "Wave" },
                    { value: "bars",  label: "Bars" },
                    { value: "pulse", label: "Pulse" }
                ]
            }
            ChoiceChipRow {
                key: "mediaVisualizerPreset"
                glyph: "󰓅"; label: "Preset"
                model: [
                    { value: "eco",      label: "Eco" },
                    { value: "balanced", label: "Balanced" },
                    { value: "smooth",   label: "Smooth" }
                ]
            }
            // the preset names say nothing about what they cost; the shape changes both
            HintText { text: Media.visualizerLabel + ". Eco uses the least CPU." }
        }
    }
}
