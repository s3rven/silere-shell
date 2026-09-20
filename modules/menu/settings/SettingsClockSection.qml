import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        ChoiceChipRow {
            glyph: "󰃭"; label: "Date"
            currentValue: !ShellSettings.clockShowDate ? "off"
                          : ShellSettings.compactDate ? "compact" : "normal"
            model: [
                { value: "off",     label: "Off"     },
                { value: "normal",  label: "Normal"  },
                { value: "compact", label: "Compact" }
            ]
            onChosen: (v) => ShellSettings.batch(() => {
                ShellSettings.clockShowDate = v !== "off"
                ShellSettings.compactDate = v === "compact"
            })
        }
        ChoiceChipRow {
            glyph: "󰔟"; label: "Time"
            currentValue: ShellSettings.clock12h ? "12h" : "24h"
            model: [
                { value: "24h", label: "24h" },
                { value: "12h", label: "12h" }
            ]
            onChosen: (v) => ShellSettings.clock12h = v === "12h"
        }
        ToggleRow {
            glyph: "󱑂"; label: "Seconds"
            key: "showSeconds"
        }
        ChoiceChipRow {
            glyph: "󰃭"; label: "Week starts"
            currentValue: ShellSettings.calendarWeekStart
            model: [
                { value: "monday", label: "Mon" },
                { value: "sunday", label: "Sun" },
                { value: "locale", label: "System" }
            ]
            onChosen: (v) => ShellSettings.calendarWeekStart = v
        }
        ToggleRow {
            glyph: "󰨲"; label: "Week numbers"
            key: "calendarWeekNumbers"
        }
    }
}
