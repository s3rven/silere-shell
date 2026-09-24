import QtQuick
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    // the chips show what the bar would, so they follow the clock's own minute tick
    function _sample(format: string): string {
        void DateTime.cachedMinute
        return Qt.formatDateTime(new Date(), format)
    }
    readonly property string _dateCore: DateTime.cachedDateCore.length > 0
        ? DateTime.cachedDateCore : root._sample("MMM dd")
    readonly property string _dayName: DateTime.cachedDayName.length > 0
        ? DateTime.cachedDayName : root._sample("ddd ")

    SectionLabel { label: "DATE"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰃭"; label: "Date"
            key: "clockShowDate"
        }
        CollapsibleSection {
            expanded: ShellSettings.clockShowDate
            ChoiceChipRow {
                glyph: "󰸗"; label: "Style"
                currentValue: ShellSettings.compactDate ? "compact" : "normal"
                model: [
                    { value: "normal",  label: root._dayName + root._dateCore },
                    { value: "compact", label: root._dateCore }
                ]
                onChosen: (v) => ShellSettings.compactDate = v === "compact"
            }
        }
    }

    SectionLabel { label: "TIME" }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰔟"; label: "Format"
            currentValue: ShellSettings.clock12h ? "12h" : "24h"
            model: [
                { value: "24h", label: root._sample("HH:mm") },
                { value: "12h", label: root._sample("h:mm AP") }
            ]
            onChosen: (v) => ShellSettings.clock12h = v === "12h"
        }
        ToggleRow {
            glyph: "󱑂"; label: "Seconds"
            key: "showSeconds"
        }
    }

    SectionLabel { label: "CALENDAR" }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰨴"; label: "Week starts"
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
