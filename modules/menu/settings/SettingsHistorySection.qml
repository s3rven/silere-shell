import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "HISTORY"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰋚"; label: "Keep after restart"
            description: "Off also clears text saved earlier"
            key: "notifHistoryPersistent"
        }
        SliderRow {
            id: _historyLimit
            glyph: "󰆙"; label: "History limit"
            displayValue: Math.round(_historyLimit.shownValue)
            key: "notifHistoryLimit"
            step: 5
            // each lower step deletes rows for good, so only the value let go of applies
            commitOnRelease: true
        }
        SelectRow {
            key: "notifHistoryDays"
            glyph: "󰥔"; label: "Keep history for"
            fallbackLabel: ShellSettings.notifHistoryDays === 0 ? "Until cleared"
                : ShellSettings.notifHistoryDays + " days"
            model: [
                { value: 0, label: "Until cleared" },
                { value: 1, label: "1 day" },
                { value: 7, label: "1 week" },
                { value: 30, label: "1 month" }
            ]
        }
        HintText {
            visible: ShellSettings.notifHistoryDays > 0
            text: "Shortening this deletes older history now."
        }
    }

    SectionLabel { label: "MUTED APPS" }
    SettingsCard {
        ControlRow {
            visible: ShellSettings.notifMutedAppNames.length === 0
            glyph: "󰂜"
            title: "No muted apps"
            status: "Mute one from its page in history"
            passive: true
        }
        // switching one off unmutes it, and the row leaves with it
        Repeater {
            model: ShellSettings.notifMutedAppNames
            delegate: ToggleRow {
                required property string modelData
                glyph: "󰪑"
                label: Notifications.appLabel(modelData)
                checked: true
                Accessible.name: "Mute popups from " + label
                onToggled: nextChecked => ShellSettings.setNotifAppMuted(modelData, nextChecked)
            }
        }
    }
}
