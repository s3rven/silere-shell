import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "POPUPS"; first: true }
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
            SliderRow {
                glyph: "󰔛"; label: "Dismiss after"
                displayValue: (ShellSettings.notifDefaultTimeout / 1000) + "s"
                key: "notifDefaultTimeout"
                step: 1000
            }
            ChoiceChipRow {
                key: "notifPosition"
                glyph: "󰍹"; label: "Position"
                model: [
                    { value: "top-left",   label: "Left"   },
                    { value: "top-center", label: "Center" },
                    { value: "top-right",  label: "Right"  }
                ]
            }
            ChoiceChipRow {
                key: "notifMaxVisible"
                glyph: "󰽘"; label: "Max shown"
                model: [
                    { value: 3, label: "3"   },
                    { value: 5, label: "5"   },
                    { value: 0, label: "All" }
                ]
            }
        }
    }

    SectionLabel { label: "HISTORY" }
    SettingsCard {
        ToggleRow {
            glyph: "󰋚"; label: "Keep after restart"
            description: "Off also clears text saved earlier"
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
                displayValue: DateTime.hourText(ShellSettings.dndFrom)
                key: "dndFrom"
            }
            SliderRow {
                glyph: "󰃰"; label: "To"
                displayValue: DateTime.hourText(ShellSettings.dndTo)
                key: "dndTo"
            }
            HintText {
                visible: ShellSettings.dndFrom === ShellSettings.dndTo
                text: "Start and end match, so nothing is silenced."
            }
        }
        ToggleRow {
            glyph: "󰀦"; label: "Let critical through"
            description: "Urgent alerts ignore do not disturb"
            key: "notifCriticalBypass"
        }
    }
}
