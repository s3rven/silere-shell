import QtQuick
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property int _calendarChipW: Math.max(_weekStart.naturalChipWidth, _units.naturalChipWidth)

    SectionLabel { label: "TIME & DATE"; first: true }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰔟"; label: "Format"
            searchKey: "clock12h"
            currentValue: ShellSettings.clock12h ? "12h" : "24h"
            // keep the focused chip alive as its preview changes
            model: [_time24, _time12]
            QtObject {
                id: _time24
                readonly property string value: "24h"
                readonly property string label: Qt.formatDateTime(DateTime.minuteSample, "HH:mm")
            }
            QtObject {
                id: _time12
                readonly property string value: "12h"
                readonly property string label: Qt.formatDateTime(DateTime.minuteSample, "h:mm AP")
            }
            onChosen: (v) => ShellSettings.clock12h = v === "12h"
        }
        ToggleRow {
            glyph: "󱑂"; label: "Seconds"
            key: "showSeconds"
        }
        ToggleRow {
            glyph: "󰃭"; label: "Date"
            key: "clockShowDate"
        }
        CollapsibleSection {
            expanded: ShellSettings.clockShowDate
            ChoiceChipRow {
                glyph: "󰸗"; label: "Style"
                searchKey: "compactDate"
                currentValue: ShellSettings.compactDate ? "compact" : "normal"
                model: [_dateNormal, _dateCompact]
                QtObject {
                    id: _dateNormal
                    readonly property string value: "normal"
                    readonly property string label: Qt.formatDateTime(DateTime.minuteSample, "ddd MMM dd")
                }
                QtObject {
                    id: _dateCompact
                    readonly property string value: "compact"
                    readonly property string label: Qt.formatDateTime(DateTime.minuteSample, "MMM dd")
                }
                onChosen: (v) => ShellSettings.compactDate = v === "compact"
            }
        }
    }

    SectionLabel { label: "CALENDAR" }
    SettingsCard {
        ChoiceChipRow {
            id: _weekStart
            key: "calendarWeekStart"
            chipWidthFloor: root._calendarChipW
            glyph: "󰨴"; label: "Week starts"
            model: [
                { value: "monday", label: "Mon" },
                { value: "sunday", label: "Sun" },
                { value: "locale", label: "System" }
            ]
        }
        ToggleRow {
            glyph: "󰨲"; label: "Week numbers"
            key: "calendarWeekNumbers"
        }
        ToggleRow {
            glyph: "󰖕"; label: "Weather"
            // off leaves the Weather service uncreated, so only read it when on
            description: "Open-Meteo, for " + (ShellSettings.weatherEnabled && Weather.place.length > 0
                ? Weather.place : "your time zone")
            key: "weatherEnabled"
        }
        CollapsibleSection {
            expanded: ShellSettings.weatherEnabled
            ToggleRow {
                glyph: "󰖕"; label: "Show on bar"
                description: "Beside the clock, refreshed every 30 min"
                key: "clockShowWeather"
            }
            ChoiceChipRow {
                id: _units
                key: "weatherUnit"
                chipWidthFloor: root._calendarChipW
                glyph: "󰔐"; label: "Units"
                model: [
                    { value: "auto", label: "Auto" },
                    { value: "c", label: "°C" },
                    { value: "f", label: "°F" }
                ]
            }
        }
    }
}
