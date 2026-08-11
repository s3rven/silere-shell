pragma ComponentBehavior: Bound

import QtQuick
import "../../../services"
import "../controls"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    readonly property bool _enabled: ShellSettings.barBorderVisible || ShellSettings.underlineGlow
    readonly property string _style: ShellSettings.underlineGlow ? "glow" : "static"
    readonly property string _screenshotStyle:
        !ShellSettings.underlineScreenshotGlow ? "off"
        : ShellSettings.screenshotGlowSweep ? "sweep"
        : "flash"

    function _setScreenshotStyle(style) {
        ShellSettings.batch(() => {
            ShellSettings.underlineScreenshotGlow = style !== "off"
            ShellSettings.screenshotGlowSweep = style === "sweep"
        })
    }

    function _setEnabled(enabled) {
        if (!enabled) {
            ShellSettings.batch(() => {
                ShellSettings.underlineLastStyle = root._style
                ShellSettings.barBorderVisible = false
                ShellSettings.underlineGlow = false
            })
            return
        }
        root._setStyle(ShellSettings.underlineLastStyle)
    }

    function _setStyle(style) {
        const next = style === "glow" ? "glow" : "static"
        ShellSettings.batch(() => {
            ShellSettings.underlineLastStyle = next
            ShellSettings.barBorderVisible = next === "static"
            ShellSettings.underlineGlow = next === "glow"
            if (next === "glow" && !ShellSettings.underlineIdleGlow
                    && !ShellSettings.underlineNotifGlow
                    && !ShellSettings.underlineBattGlow
                    && !ShellSettings.underlineNetGlow
                    && !ShellSettings.underlineTempGlow
                    && !ShellSettings.underlineScreenshotGlow) {
                ShellSettings.underlineNotifGlow = true
                ShellSettings.underlineNetGlow = true
            }
        })
    }

    // pairs with EVENTS below: both headings appear together, so a lone card is never labelled
    CollapsibleSection {
        expanded: ShellSettings.underlineGlow
        SectionLabel { label: "APPEARANCE"; first: true }
    }

    SettingsCard {
        ToggleRow {
            glyph: "󰍴"; label: "Underline"
            checked: root._enabled
            onToggled: nextChecked => root._setEnabled(nextChecked)
        }
        CollapsibleSection {
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
                // the glow layers saturate their own clamps by 1.7; only the static line has room above 2
                min: 0.5; max: ShellSettings.underlineGlow ? 2.0 : 3.0; step: 0.05
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
                expanded: ShellSettings.underlineGlow
                ToggleRow {
                    glyph: "󰊠"; label: "Ambient glow"
                    key: "underlineIdleGlow"
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
                            key: "underlineNotifGlow"
                        }
                        ToggleRow {
                            glyph: "󰤭"; label: "Network disconnect"
                            key: "underlineNetGlow"
                        }
                        ToggleRow {
                            glyph: "󱃍"; label: "Battery low"
                            key: "underlineBattGlow"
                        }
                        ToggleRow {
                            glyph: "󰔏"; label: "Temperature"
                            key: "underlineTempGlow"
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
                        HintText {
                            // reactive mode drops the static line, so with no source at all the bar shows nothing
                            visible: !ShellSettings.underlineIdleGlow
                                && !ShellSettings.underlineNotifGlow
                                && !ShellSettings.underlineNetGlow
                                && !ShellSettings.underlineBattGlow
                                && !ShellSettings.underlineTempGlow
                                && !ShellSettings.underlineScreenshotGlow
                                && !ShellSettings.mediaProgress
                            text: "Nothing lights the underline yet; turn on an event above or Ambient glow."
                        }
                    }
                }
            }
        }
    }
}
