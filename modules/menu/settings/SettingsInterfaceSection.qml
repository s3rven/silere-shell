pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property bool _hasBrightnessChoice: Brightness.devices.length > 1
        || ShellSettings.brightnessDevice.length > 0
    readonly property bool _hasMultiScreen: Quickshell.screens.length > 1
    readonly property bool _hasOverlayChoice: _hasMultiScreen
        || ShellSettings.overlayMonitor.length > 0
    readonly property bool _hasRouting: _hasBrightnessChoice || _hasOverlayChoice

    readonly property var _nightLightChoices: {
        const auto = Settings.autoNightLightProvider
        const out = [{ value: "auto",
            label: auto.length > 0 ? "Automatic (" + auto + ")" : "Automatic (none found)" }]
        const named = [
            { value: "hyprsunset", label: "hyprsunset",
              ok: Compositor.isHyprland && SystemTools.hasHyprsunset },
            { value: "wlsunset",   label: "wlsunset",   ok: SystemTools.hasWlsunset   }
        ]
        for (let i = 0; i < named.length; i++) {
            if (named[i].value === "hyprsunset" && !Compositor.isHyprland) continue
            out.push({ value: named[i].value,
                label: named[i].ok ? named[i].label : named[i].label + " (not installed)" })
        }
        return out
    }

    readonly property var _lockChoices: {
        const auto = Settings.autoLockProvider
        const out = [{ value: "auto",
            label: auto.length > 0 ? "Automatic (" + auto + ")" : "Automatic (none found)" }]
        const named = [
            { value: "hyprlock", label: "hyprlock",             ok: SystemTools.hasHyprlock },
            { value: "swaylock", label: "swaylock",             ok: SystemTools.hasSwaylock },
            { value: "gtklock",  label: "gtklock",              ok: SystemTools.hasGtklock  },
            { value: "loginctl", label: "loginctl lock-session", ok: SystemTools.hasLoginctl }
        ]
        for (let i = 0; i < named.length; i++)
            out.push({ value: named[i].value,
                label: named[i].ok ? named[i].label : named[i].label + " (not installed)" })
        out.push({ value: "custom", label: "Custom command" })
        return out
    }

    Component.onCompleted: {
        SystemTools.refreshIfStale(60000)
        FontScan.requestScan()
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
            expanded: FontScan.scanned
            HintText {
                text: FontScan.families.length > 0
                    ? "Nerd Fonts only, so the shell's icons render."
                    : "No Nerd Font found; shell icons render as boxes until one is installed."
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
                { value: 1.15, label: "115%" }
            ]
        }
        SelectRow {
            key: "barIconSize"
            glyph: "󰀻"; label: "Icon size"
            description: "Tray and workspace app icons"
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
            description: "Disable transitions and animated effects"
            key: "reduceMotion"
        }
    }

    SectionLabel { label: "MENU" }
    SettingsCard {
        ToggleRow {
            glyph: "󱂪"; label: "Keep groups open"
            description: "Sidebar starts with every group expanded"
            key: "settingsNavPinned"
        }
    }

    CollapsibleSection {
        expanded: root._hasRouting

        SectionLabel { label: "DISPLAYS" }
        SettingsCard {
            CollapsibleSection {
                expanded: root._hasBrightnessChoice
                SelectRow {
                    key: "brightnessDevice"
                    glyph: "󰃟"; label: "Brightness display"
                    description: "Backlight the slider adjusts"
                    fallbackLabel: ShellSettings.brightnessDevice + " (unavailable)"
                    model: Brightness.deviceChoices
                }
            }

            CollapsibleSection {
                expanded: root._hasOverlayChoice
                SelectRow {
                    key: "overlayMonitor"
                    glyph: "󰍹"; label: "Overlay display"
                    description: "Where popups and the OSD appear"
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
    }

    SectionLabel { label: "SYSTEM PROGRAMS" }
    SettingsCard {
        SelectRow {
            key: "lockProvider"
            glyph: "󰌾"; label: "Screen lock"
            model: root._lockChoices
        }
        HintText {
            visible: ShellSettings.lockProvider === "custom"
                && Settings.customLockCommand.length === 0
            text: "No command set yet. Run: silere ipc settings set lockCommandCustom \"swaylock -f\""
        }
        HintText {
            visible: ShellSettings.lockProvider !== "custom"
                && Settings.lockCommand.length === 0
            text: "The chosen lock program is not installed, so the lock action stays off."
        }
        SelectRow {
            key: "nightLightProvider"
            glyph: "󰖙"; label: "Night light"
            model: root._nightLightChoices
        }
        HintText {
            visible: Settings.nightLightTool.length === 0
            text: ShellSettings.nightLightProvider !== "auto"
                ? "The chosen program is unavailable. Choose Automatic or install a compatible program."
                : Compositor.isHyprland
                    ? "Install hyprsunset or wlsunset to enable night light."
                    : "Install wlsunset to enable night light on this compositor."
        }
    }
}
