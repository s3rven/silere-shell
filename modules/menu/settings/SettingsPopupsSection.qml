import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "GENERAL"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰂚"; label: "Popup notifications"
            key: "notifPopupEnabled"
        }
        CollapsibleSection {
            expanded: ShellSettings.notifPopupEnabled
            ToggleRow {
                glyph: "󰊓"; label: "Hide in fullscreen"
                key: "notifFullscreenSilence"
            }
        }
    }

    CollapsibleSection {
        expanded: ShellSettings.notifPopupEnabled

        SectionLabel { label: "DISPLAY" }
        SettingsCard {
            SliderRow {
                glyph: "󰔛"; label: "Dismiss after"
                displayValue: (ShellSettings.notifDefaultTimeout / 1000) + "s"
                key: "notifDefaultTimeout"
                step: 1000
            }
            ChoiceChipRow {
                glyph: "󰍹"; label: "Position"
                currentValue: ShellSettings.notifPosition
                model: [
                    { value: "top-left",   label: "Left"   },
                    { value: "top-center", label: "Center" },
                    { value: "top-right",  label: "Right"  }
                ]
                onChosen: (v) => ShellSettings.notifPosition = v
            }
            ChoiceChipRow {
                glyph: "󰽘"; label: "Max shown"
                currentValue: ShellSettings.notifMaxVisible
                model: [
                    { value: 3, label: "3"   },
                    { value: 5, label: "5"   },
                    { value: 0, label: "All" }
                ]
                onChosen: (v) => ShellSettings.notifMaxVisible = v
            }
        }
    }

    SectionLabel { label: "HISTORY" }
    SettingsCard {
        ToggleRow {
            glyph: "󰋚"; label: "Keep after restart"
            description: "Otherwise clear saved text and keep this session only"
            key: "notifHistoryPersistent"
        }
        SliderRow {
            glyph: "󰆙"; label: "History limit"
            displayValue: ShellSettings.notifHistoryLimit
            key: "notifHistoryLimit"
            step: 5
        }
    }

    SectionLabel { label: "QUIET HOURS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰂛"; label: "Scheduled do not disturb"
            key: "dndSchedule"
        }
        CollapsibleSection {
            expanded: ShellSettings.dndSchedule
            SliderRow {
                glyph: "󰃰"; label: "From"
                displayValue: (ShellSettings.dndFrom < 10 ? "0" : "") + ShellSettings.dndFrom + ":00"
                key: "dndFrom"
            }
            SliderRow {
                glyph: "󰃰"; label: "To"
                displayValue: (ShellSettings.dndTo < 10 ? "0" : "") + ShellSettings.dndTo + ":00"
                key: "dndTo"
            }
        }
    }
}
