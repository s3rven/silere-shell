pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "TEXT & ACCESSIBILITY"; first: true }
    SettingsCard {
        SelectRow {
            glyph: "󰛖"; label: "Font"
            description: "Typeface used for text and shell icons"
            currentValue: ShellSettings.fontFamily
            model: {
                const m = [{
                    value: "",
                    label: "JetBrainsMono (default)",
                    fontFamily: "JetBrainsMono Nerd Font"
                }]
                const fams = FontScan.families
                for (let i = 0; i < fams.length; i++) {
                    const f = fams[i]
                    if (f === "JetBrainsMono Nerd Font") continue
                    m.push({
                        value: f,
                        label: f.replace(/ Nerd Font( Mono)?$/, ""),
                        fontFamily: f
                    })
                }
                const cur = ShellSettings.fontFamily
                if (cur.length > 0 && m.findIndex(e => e.value === cur) < 0) {
                    m.push({
                        value: cur,
                        label: cur.replace(/ Nerd Font( Mono)?$/, "") + " (not installed)"
                    })
                }
                return m
            }
            onChosen: (v) => ShellSettings.fontFamily = v
        }
        SelectRow {
            glyph: "󰍉"; label: "UI scale"
            description: "Size of the bar, panels, and controls"
            currentValue: ShellSettings.uiScale
            model: [
                { value: 0.8,  label: "80%"  },
                { value: 0.9,  label: "90%"  },
                { value: 1.0,  label: "100%" },
                { value: 1.1,  label: "110%" },
                { value: 1.15, label: "115%" }
            ]
            onChosen: (v) => ShellSettings.uiScale = v
        }
        ToggleRow {
            glyph: "󰹑"; label: "High contrast"
            description: "Strengthen boundaries and selected states"
            checked: ShellSettings.highContrast
            onToggled: ShellSettings.highContrast = !ShellSettings.highContrast
        }
        ToggleRow {
            glyph: "󱖳"; label: "Reduce motion"
            description: "Use instant transitions throughout the shell"
            checked: ShellSettings.reduceMotion
            onToggled: ShellSettings.reduceMotion = !ShellSettings.reduceMotion
        }
    }

    SectionLabel {
        label: "DISPLAY ROUTING"
        visible: Brightness.devices.length > 1 || Quickshell.screens.length > 1
    }
    SettingsCard {
        visible: Brightness.devices.length > 1 || Quickshell.screens.length > 1

        SelectRow {
            visible: Brightness.devices.length > 1
            glyph: "󰃟"; label: "Brightness control"
            description: "Display adjusted by the brightness widget"
            currentValue: Brightness.deviceChoice
            model: Brightness.deviceChoices
            onChosen: (v) => ShellSettings.brightnessDevice = v
        }

        SelectRow {
            visible: Quickshell.screens.length > 1
            glyph: "󰍹"; label: "Popups and OSD"
            description: "Choose a display or follow keyboard focus"
            currentValue: ShellSettings.overlayMonitor
            model: {
                const choices = [{ value: "", label: "Follow focus" }]
                const screens = Quickshell.screens || []
                for (let i = 0; i < screens.length; i++) {
                    const name = screens[i].name
                    choices.push({ value: name, label: name })
                }
                return choices
            }
            onChosen: (v) => ShellSettings.overlayMonitor = v
        }

        Repeater {
            model: Quickshell.screens.length > 1 ? Quickshell.screens : []
            delegate: ToggleRow {
                required property var modelData
                glyph: "󰍺"
                label: "Bar on " + modelData.name
                checked: Monitors.barEnabled(modelData)
                onToggled: Monitors.setBarEnabled(modelData.name, !checked)
            }
        }
    }
}
