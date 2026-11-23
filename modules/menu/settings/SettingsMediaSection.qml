import QtQuick
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    readonly property int _chipW: Math.max(_position.naturalChipWidth,
        _shape.naturalChipWidth, _preset.naturalChipWidth)

    Component.onCompleted: SystemTools.refreshIfStale(60000)

    SectionLabel { label: "NOW PLAYING"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰎇"; label: "Artist"
            searchKey: "mediaWidgetFormat"
            checked: ShellSettings.mediaWidgetFormat === "artist-title"
            onToggled: nextChecked => ShellSettings.mediaWidgetFormat =
                nextChecked ? "artist-title" : "title"
        }
        ToggleRow {
            glyph: "󰐊"; label: "Playback status"
            key: "mediaWidgetHelper"
        }
        ToggleRow {
            glyph: "󰥶"; label: "Cover art from the web"
            description: "Image hosts can see what you play"
            key: "mediaRemoteArt"
            available: !SystemTools.ready || Media.remoteArtAvailable
            dependsNote: "No curl"
        }
        ToggleRow {
            glyph: "󰟎"; label: "Pause when headphones disconnect"
            description: "Bluetooth and USB, not the headphone jack"
            key: "mediaPauseOnDisconnect"
        }
    }

    SectionLabel { label: "VISUALIZER" }
    SettingsCard {
        ToggleRow {
            id: _visualizerToggle
            glyph: "󰱐"; label: "Audio visualizer"
            description: Media.visualizerStatus
            key: "mediaProgress"
            available: !SystemTools.ready || Media.cavaAvailable
            dependsNote: !SystemTools.ready ? "Checking"
                : !SystemTools.hasCava ? "No cava" : "Runtime unavailable"
        }
        ControlRow {
            visible: Media.visualizerError.length > 0
            glyph: "󰑐"; title: "Retry visualizer"
            onActivated: {
                if (activeFocus) _visualizerToggle.forceActiveFocus(Qt.TabFocusReason)
                Media.retryVisualizer()
            }
        }
        CollapsibleSection {
            expanded: ShellSettings.mediaProgress && Media.cavaAvailable
            ChoiceChipRow {
                id: _position
                key: "mediaVisualizerPosition"
                chipWidthFloor: root._chipW
                glyph: "󰍹"; label: "Position"
                model: [
                    { value: "media",     label: "Media" },
                    { value: "center",    label: "Center" },
                    { value: "underline", label: "Underline" }
                ]
            }
            ChoiceChipRow {
                id: _shape
                key: "mediaVisualizerStyle"
                chipWidthFloor: root._chipW
                glyph: "󰀁"; label: "Shape"
                model: [
                    { value: "wave",  label: "Wave" },
                    { value: "bars",  label: "Bars" },
                    { value: "pulse", label: "Pulse" }
                ]
            }
            ChoiceChipRow {
                id: _preset
                key: "mediaVisualizerPreset"
                chipWidthFloor: root._chipW
                glyph: "󰓅"; label: "Preset"
                model: [
                    { value: "eco",      label: "Eco" },
                    { value: "balanced", label: "Balanced" },
                    { value: "smooth",   label: "Smooth" }
                ]
            }
        }
    }
}
