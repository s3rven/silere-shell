import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    property bool _armed: false

    function _disarm(): void {
        root._armed = false
        _armTimer.stop()
    }

    Timer {
        id: _armTimer
        interval: 3000
        onTriggered: root._armed = false
    }

    Connections {
        target: MenuState
        function onSettingsSectionChanged() { root._disarm() }
        function onOpenChanged() { if (!MenuState.open) root._disarm() }
    }

    SettingsCard {
        ControlRow {
            glyph: "󰦛"
            title: root._armed ? "Confirm reset" : "Restore default settings"
            status: ShellSettings.modifiedCount > 0
                ? ShellSettings.modifiedCount + (ShellSettings.modifiedCount === 1
                    ? " setting changed" : " settings changed")
                : "Everything is at its default"
            valueText: root._armed ? "Tap again" : ""
            accentColor: root._armed ? Theme.error : Theme.accent
            active: root._armed
            available: ShellSettings.modifiedCount > 0
            onActivated: {
                if (root._armed) {
                    root._disarm()
                    ShellSettings.resetToDefaults()
                } else {
                    root._armed = true
                    _armTimer.restart()
                }
            }
        }
        HintText {
            text: "Restores appearance, behavior, and layout to their built-in defaults. "
                + "Your wallpaper theme and calendar marks are untouched."
        }
    }
}
