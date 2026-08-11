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
            checked: ShellSettings.notifPopupEnabled
            onToggled: nextChecked => ShellSettings.notifPopupEnabled = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.notifPopupEnabled
            ToggleRow {
                glyph: "󰊓"; label: "Hide in fullscreen"
                checked: ShellSettings.notifFullscreenSilence
                onToggled: nextChecked => ShellSettings.notifFullscreenSilence = nextChecked
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
                value: ShellSettings.notifDefaultTimeout
                min: 1000; max: 30000; step: 1000
                onChanged: (v) => ShellSettings.notifDefaultTimeout = v
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
            checked: ShellSettings.notifHistoryPersistent
            onToggled: nextChecked => ShellSettings.notifHistoryPersistent = nextChecked
        }
        SliderRow {
            glyph: "󰒓"; label: "History limit"
            displayValue: ShellSettings.notifHistoryLimit
            value: ShellSettings.notifHistoryLimit
            min: 5; max: 100; step: 5
            onChanged: (v) => ShellSettings.notifHistoryLimit = Math.round(v)
        }
    }

    SectionLabel { label: "QUIET HOURS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰂛"; label: "Scheduled do not disturb"
            checked: ShellSettings.dndSchedule
            onToggled: nextChecked => ShellSettings.dndSchedule = nextChecked
        }
        CollapsibleSection {
            expanded: ShellSettings.dndSchedule
            SliderRow {
                glyph: "󰃰"; label: "From"
                displayValue: (ShellSettings.dndFrom < 10 ? "0" : "") + ShellSettings.dndFrom + ":00"
                value: ShellSettings.dndFrom
                min: 0; max: 23; step: 1
                onChanged: (v) => ShellSettings.dndFrom = v
            }
            SliderRow {
                glyph: "󰃰"; label: "To"
                displayValue: (ShellSettings.dndTo < 10 ? "0" : "") + ShellSettings.dndTo + ":00"
                value: ShellSettings.dndTo
                min: 0; max: 23; step: 1
                onChanged: (v) => ShellSettings.dndTo = v
            }
        }
    }
}
