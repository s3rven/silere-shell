pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "TEXT & ACCESSIBILITY"; first: true }
    SettingsCard {
        SelectRow {
            glyph: "󰛖"; label: "Font"
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
        HintText {
            visible: FontScan.scanned && FontScan.families.length === 0
            text: "No Nerd Font found; shell icons render as boxes until one is installed."
        }
        SelectRow {
            glyph: "󰍉"; label: "UI scale"
            currentValue: ShellSettings.uiScale
            fallbackLabel: Math.round(ShellSettings.uiScale * 100) + "%"
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
            checked: ShellSettings.highContrast
            onToggled: nextChecked => ShellSettings.highContrast = nextChecked
        }
        ToggleRow {
            glyph: "󱂪"; label: "Keep groups open"
            description: "Show multiple category groups"
            checked: ShellSettings.settingsNavPinned
            onToggled: nextChecked => ShellSettings.settingsNavPinned = nextChecked
        }
        ToggleRow {
            glyph: "󱖳"; label: "Reduce motion"
            description: "Disable transitions"
            checked: ShellSettings.reduceMotion
            onToggled: nextChecked => ShellSettings.reduceMotion = nextChecked
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
            glyph: "󰃟"; label: "Brightness display"
            currentValue: Brightness.deviceChoice
            model: Brightness.deviceChoices
            onChosen: (v) => ShellSettings.brightnessDevice = v
        }

        SelectRow {
            visible: Quickshell.screens.length > 1
            glyph: "󰍹"; label: "Overlay display"
            description: "Follow focus or choose a display"
            currentValue: ShellSettings.overlayMonitor
            fallbackLabel: ShellSettings.overlayMonitor.length > 0
                ? ShellSettings.overlayMonitor + " (unavailable)" : "Follow focus"
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
                onToggled: nextChecked => Monitors.setBarEnabled(
                    modelData.name, nextChecked)
            }
        }
    }
}
