pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property bool _hasBrightnessChoice: Brightness.devices.length > 1
    readonly property bool _hasMultiScreen: Quickshell.screens.length > 1
    readonly property bool _hasRouting: _hasBrightnessChoice || _hasMultiScreen

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
        // the list is a small slice of what fc-list reports, and an installed font missing
        // from it reads as a broken scan rather than a deliberate filter
        HintText {
            visible: FontScan.scanned && FontScan.families.length > 0
            text: "Nerd Fonts only — the shell draws its icons as glyphs, so other fonts show boxes."
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
        SelectRow {
            glyph: "󰀻"; label: "Icon size"
            description: "Tray and workspace app icons"
            currentValue: ShellSettings.barIconSize
            fallbackLabel: ShellSettings.barIconSize + "px"
            model: [
                { value: 12, label: "Normal" },
                { value: 15, label: "Large"  },
                { value: 18, label: "XL"     }
            ]
            onChosen: (v) => ShellSettings.barIconSize = v
        }
        ToggleRow {
            glyph: "󰆖"; label: "High contrast"
            key: "highContrast"
        }
        ToggleRow {
            glyph: "󱖳"; label: "Reduce motion"
            description: "Disable transitions"
            key: "reduceMotion"
        }
    }

    SectionLabel { label: "MENU" }
    SettingsCard {
        ToggleRow {
            glyph: "󱂪"; label: "Keep groups open"
            description: "Show multiple category groups"
            key: "settingsNavPinned"
        }
        ToggleRow {
            glyph: "󰧞"; label: "Mark changed pages"
            description: "Dot the categories holding a changed setting"
            key: "settingsNavDots"
        }
    }

    SectionLabel {
        label: "DISPLAY ROUTING"
        visible: root._hasRouting
    }
    SettingsCard {
        visible: root._hasRouting

        SelectRow {
            visible: root._hasBrightnessChoice
            glyph: "󰃟"; label: "Brightness display"
            currentValue: Brightness.deviceChoice
            model: Brightness.deviceChoices
            onChosen: (v) => ShellSettings.brightnessDevice = v
        }

        SelectRow {
            visible: root._hasMultiScreen
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
            model: root._hasMultiScreen ? Quickshell.screens : []
            delegate: ToggleRow {
                required property var modelData
                glyph: "󰍺"
                label: "Bar on " + modelData.name
                checked: Monitors.barEnabled(modelData)
                // turning off the last one is refused, and a switch that springs back with no reason reads as a broken toggle
                enabled: !checked || Monitors.liveBarCount > 1
                dependsNote: "Keeps the menu reachable"
                onToggled: nextChecked => Monitors.setBarEnabled(
                    modelData.name, nextChecked)
            }
        }
    }
}
