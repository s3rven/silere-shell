import QtQuick
import "../../services"

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
            onChosen: (v) => {
                ShellSettings.clockShowDate = v !== "off"
                ShellSettings.compactDate = v === "compact"
            }
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
            checked: ShellSettings.showSeconds
            onToggled: ShellSettings.showSeconds = !ShellSettings.showSeconds
        }
    }
}
