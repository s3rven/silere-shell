import QtQuick
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        ToggleRow {
            glyph: "󰂚"; label: "Popup notifications"
            checked: ShellSettings.notifPopupEnabled
            onToggled: ShellSettings.notifPopupEnabled = !ShellSettings.notifPopupEnabled
        }
        ToggleRow {
            glyph: "󰊓"; label: "Hide in fullscreen"
            enabled: ShellSettings.notifPopupEnabled
            checked: ShellSettings.notifFullscreenSilence
            onToggled: ShellSettings.notifFullscreenSilence = !ShellSettings.notifFullscreenSilence
        }
    }

    SectionLabel { label: "DISPLAY" }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰔛"; label: "Dismiss after"
            enabled: ShellSettings.notifPopupEnabled
            currentValue: ShellSettings.notifDefaultTimeout
            model: [
                { value: 3000,  label: "3s"  },
                { value: 5000,  label: "5s"  },
                { value: 10000, label: "10s" },
                { value: 15000, label: "15s" }
            ]
            onChosen: (v) => ShellSettings.notifDefaultTimeout = v
        }
        ChoiceChipRow {
            glyph: "󰍹"; label: "Position"
            enabled: ShellSettings.notifPopupEnabled
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
            enabled: ShellSettings.notifPopupEnabled
            currentValue: ShellSettings.notifMaxVisible
            model: [
                { value: 3, label: "3"   },
                { value: 5, label: "5"   },
                { value: 0, label: "All" }
            ]
            onChosen: (v) => ShellSettings.notifMaxVisible = v
        }
    }

    SectionLabel { label: "QUIET HOURS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰂛"; label: "Auto do not disturb"
            checked: ShellSettings.dndSchedule
            onToggled: ShellSettings.dndSchedule = !ShellSettings.dndSchedule
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
