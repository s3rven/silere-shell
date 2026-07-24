import QtQuick
import "../../services"

Column {
    id: root

    // the section is destroyed on navigate-away, so the "restore my last mode" memory lives on the page
    property string lastStyle: "static"
    signal styleRemembered(string style)

    width: parent ? parent.width : 0
    spacing: 0

    readonly property bool _enabled: ShellSettings.barBorderVisible || ShellSettings.underlineGlow
    readonly property string _style: ShellSettings.underlineGlow ? "glow" : "static"
    readonly property string _screenshotStyle:
        !ShellSettings.underlineScreenshotGlow ? "off"
        : ShellSettings.screenshotGlowSweep ? "sweep"
        : "flash"

    function _setScreenshotStyle(style) {
        ShellSettings.underlineScreenshotGlow = style !== "off"
        ShellSettings.screenshotGlowSweep = style === "sweep"
    }

    function _setEnabled(enabled) {
        if (!enabled) {
            root.styleRemembered(root._style)
            ShellSettings.barBorderVisible = false
            ShellSettings.underlineGlow = false
            return
        }
        root._setStyle(root.lastStyle)
    }

    function _setStyle(style) {
        root.styleRemembered(style)
        ShellSettings.barBorderVisible = style === "static"
        ShellSettings.underlineGlow = style === "glow"
        if (style === "glow" && !ShellSettings.underlineIdleGlow
                && !ShellSettings.underlineNotifGlow
                && !ShellSettings.underlineBattGlow
                && !ShellSettings.underlineNetGlow
                && !ShellSettings.underlineTempGlow
                && !ShellSettings.underlineScreenshotGlow) {
            ShellSettings.underlineNotifGlow = true
            ShellSettings.underlineNetGlow = true
        }
    }

    SettingsCard {
        ToggleRow {
            glyph: "󰍴"; label: "Underline"
            checked: root._enabled
            onToggled: root._setEnabled(!root._enabled)
        }
        CollapsibleSection {
            indent: 8
            expanded: root._enabled
            ChoiceChipRow {
                glyph: "󰒓"; label: "Mode"
                currentValue: root._style
                model: [
                    { value: "static", label: "Line" },
                    { value: "glow",   label: "Reactive" }
                ]
                onChosen: (v) => root._setStyle(v)
            }
            SliderRow {
                glyph: "󰃠"
                label: ShellSettings.underlineGlow ? "Glow strength" : "Line strength"
                value: ShellSettings.underlineGlow ? ShellSettings.glowStrength : ShellSettings.barLineStrength
                min: 0.5; max: 2.0; step: 0.05
                displayValue: Math.round((ShellSettings.underlineGlow
                    ? ShellSettings.glowStrength : ShellSettings.barLineStrength) * 100) + "%"
                onChanged: (v) => {
                    if (ShellSettings.underlineGlow) {
                        ShellSettings.glowStrength = v
                    } else {
                        ShellSettings.barLineStrength = v
                    }
                }
            }
            CollapsibleSection {
                indent: 8
                expanded: ShellSettings.underlineGlow
                ToggleRow {
                    glyph: "󰊠"; label: "Ambient glow"
                    checked: ShellSettings.underlineIdleGlow
                    onToggled: ShellSettings.underlineIdleGlow = !ShellSettings.underlineIdleGlow
                }
            }
        }
    }

    CollapsibleSection {
        id: _glowSection
        expanded: ShellSettings.underlineGlow
        Loader {
            width: parent.width
            active: ShellSettings.underlineGlow || _glowSection.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: Component {
                Column {
                    width: parent.width
                    SectionLabel { label: "EVENTS" }
                    SettingsCard {
                        ToggleRow {
                            glyph: "󰂚"; label: "Notifications"
                            checked: ShellSettings.underlineNotifGlow
                            onToggled: ShellSettings.underlineNotifGlow = !ShellSettings.underlineNotifGlow
                        }
                        ToggleRow {
                            glyph: "󰤭"; label: "Network disconnect"
                            checked: ShellSettings.underlineNetGlow
                            onToggled: ShellSettings.underlineNetGlow = !ShellSettings.underlineNetGlow
                        }
                        ToggleRow {
                            glyph: "󱃍"; label: "Battery low"
                            checked: ShellSettings.underlineBattGlow
                            onToggled: ShellSettings.underlineBattGlow = !ShellSettings.underlineBattGlow
                        }
                        ToggleRow {
                            glyph: "󰔏"; label: "Temperature"
                            checked: ShellSettings.underlineTempGlow
                            onToggled: ShellSettings.underlineTempGlow = !ShellSettings.underlineTempGlow
                        }
                        ChoiceChipRow {
                            glyph: "󰄀"; label: "Screenshots"
                            enabled: SystemTools.hasInotifywait
                            currentValue: root._screenshotStyle
                            model: [
                                { value: "off",   label: "Off" },
                                { value: "flash", label: "Flash" },
                                { value: "sweep", label: "Sweep" }
                            ]
                            onChosen: (v) => root._setScreenshotStyle(v)
                        }
                        HintText {
                            visible: !SystemTools.hasInotifywait
                            text: "Screenshot feedback needs inotify-tools."
                        }
                    }
                }
            }
        }
    }
}
