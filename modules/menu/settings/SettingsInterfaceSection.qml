pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    // opening the page is the refresh: fonts installed since the last visit show up here
    Component.onCompleted: {
        SystemTools.refreshIfStale(60000)
        FontScan.refreshIfStale(60000)
    }

    SectionLabel { label: "TEXT & ACCESSIBILITY"; first: true }
    SettingsCard {
        SelectRow {
            key: "fontFamily"
            glyph: "󰛖"; label: "Font"
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
        }
        CollapsibleSection {
            expanded: FontScan.lastError.length > 0
                || (FontScan.scanned && FontScan.iconFamilies.length === 0)
            HintText {
                text: FontScan.lastError.length > 0 ? FontScan.lastError
                    : "No Nerd Font found; shell icons render as boxes until one is installed."
                textColor: FontScan.lastError.length > 0 ? Theme.menuTextWarning : Theme.menuTextDetail
            }
        }
        SelectRow {
            key: "uiScale"
            glyph: "󰍉"; label: "UI scale"
            fallbackLabel: Math.round(ShellSettings.uiScale * 100) + "%"
            model: [
                { value: 0.8,  label: "80%"  },
                { value: 0.9,  label: "90%"  },
                { value: 1.0,  label: "100%" },
                { value: 1.1,  label: "110%" },
                { value: 1.15, label: "115%" },
                { value: 1.25, label: "125%" },
                { value: 1.5, label: "150% (comfortable)" }
            ]
        }
        SelectRow {
            key: "barIconSize"
            glyph: "󰀻"; label: "Icon size"
            fallbackLabel: ShellSettings.barIconSize + "px"
            model: [
                { value: 12, label: "Normal" },
                { value: 15, label: "Large"  },
                { value: 18, label: "XL"     }
            ]
        }
        ToggleRow {
            glyph: "󰆖"; label: "High contrast"
            key: "highContrast"
        }
        ToggleRow {
            glyph: "󱖳"; label: "Reduce motion"
            key: "reduceMotion"
        }
    }

    SectionLabel { label: "MENU" }
    SettingsCard {
        ToggleRow {
            glyph: "󱂪"; label: "Keep groups open"
            key: "settingsNavPinned"
        }
    }
}
