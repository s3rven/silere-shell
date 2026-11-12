pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../controls"

// the machine side of the settings: which display, light and radio Silere drives, and the programs it runs
Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property bool _hasBrightnessChoice: Brightness.devices.length > 1
        || ShellSettings.brightnessDevice.length > 0
    readonly property bool _hasMultiScreen: Quickshell.screens.length > 1
    readonly property bool _hasOverlayChoice: _hasMultiScreen
        || ShellSettings.overlayMonitor.length > 0

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

    // opening the page is the refresh: programs installed since the last visit and newly attached displays show up here
    Component.onCompleted: {
        SystemTools.refreshIfStale(60000)
        if (ShellSettings.ddcBrightnessEnabled) DisplayBrightness.refresh(false)
        Session.refresh()
    }

    SectionLabel { label: "DISPLAYS"; first: true }
    SettingsCard {
        CollapsibleSection {
            expanded: root._hasBrightnessChoice
            SelectRow {
                key: "brightnessDevice"
                glyph: "󰃟"; label: "Brightness display"
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
                onChosen: value => Monitors.selectOverlay(String(value))
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
                    blocked: checked && Monitors.liveBarCount <= 1
                    dependsNote: "Keeps the menu reachable"
                    onToggled: nextChecked => Monitors.setBarEnabled(
                        modelData.name, nextChecked)
                }
            }
        }

        ToggleRow {
            glyph: "󰹑"; label: "External brightness"
            key: "ddcBrightnessEnabled"
            available: DisplayBrightness.supported
            dependsNote: SystemTools.preview ? "Not in the preview" : "Needs ddcutil and timeout"
        }
        HintText {
            visible: ShellSettings.ddcBrightnessEnabled && text.length > 0
            text: DisplayBrightness.scanning ? "Checking external displays…"
                : DisplayBrightness.lastError.length > 0 ? DisplayBrightness.lastError
                : DisplayBrightness.displays.length === 0 ? "No DDC/CI display found. Check its DDC/CI option and I2C access."
                : ""
        }
        Repeater {
            model: ShellSettings.ddcBrightnessEnabled ? DisplayBrightness.displays : []
            ToggleRow {
                required property var modelData
                glyph: "󰹑"
                label: "Control " + modelData.label
                checked: !DisplayBrightness.disabled(modelData.key)
                onToggled: nextChecked => DisplayBrightness.setEnabled(modelData.key, nextChecked)
            }
        }
    }

    CollapsibleSection {
        expanded: KeyboardBrightness.devices.length > 1
        SectionLabel { label: "KEYBOARD LIGHTING" }
        SettingsCard {
            SelectRow {
                glyph: "󰌌"
                label: "Keyboard light"
                description: "Applies to this session"
                model: KeyboardBrightness.choices
                currentValue: KeyboardBrightness.key
                onChosen: value => KeyboardBrightness.preferredKey = String(value)
            }
        }
    }

    CollapsibleSection {
        expanded: Bluetooth.adapterCount > 1
        SectionLabel { label: "BLUETOOTH" }
        SettingsCard {
            SelectRow {
                glyph: "󰂯"
                label: "Controller"
                description: "Applies to this session"
                model: Bluetooth.adapterChoices
                currentValue: Bluetooth.adapterChoice
                onChosen: value => Bluetooth.selectAdapter(String(value))
            }
        }
    }

    SectionLabel { label: "PROGRAMS" }
    SettingsCard {
        SelectRow {
            key: "lockProvider"
            glyph: "󰌾"; label: "Screen lock"
            model: root._lockChoices
        }
        CollapsibleSection {
            expanded: ShellSettings.lockProvider === "custom"
            LockCommandEditor {}
        }
        HintText {
            visible: text.length > 0
            text: Session.lastError.length > 0 ? Session.lastError
                : Session.canLockSleep ? "" : Session.readiness
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
