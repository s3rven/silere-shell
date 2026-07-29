import QtQuick
import "../../config"
import "../../services"

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: 0

    function _alertMode(osdEnabled, glowEnabled): string {
        const o = osdEnabled === true
        const g = glowEnabled === true && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setAlertMode(v, osdKey, glowKey): void {
        ShellSettings[osdKey] = (v === "osd" || v === "both")
        ShellSettings[glowKey] = (v === "glow" || v === "both")
    }

    readonly property string _battAlertMode: root._alertMode(
        ShellSettings.osdBatteryWarn, ShellSettings.underlineBattGlow)
    readonly property string _tempAlertMode: root._alertMode(
        ShellSettings.osdTempWarn, ShellSettings.underlineTempGlow)

    readonly property var _alertChipModel: ShellSettings.underlineGlow
        ? [
            { value: "off",  label: "Off"  },
            { value: "osd",  label: "OSD"  },
            { value: "glow", label: "Glow" },
            { value: "both", label: "Both" }
        ]
        : [
            { value: "off", label: "Off" },
            { value: "osd", label: "OSD" }
          ]

    SectionLabel { label: "BATTERY"; first: true; visible: Battery.available }
    SettingsCard {
        visible: Battery.available
        ChoiceChipRow {
            glyph: "󱟢"; label: "Low battery alert"
            currentValue: root._battAlertMode
            model: root._alertChipModel
            onChosen: (v) => root._setAlertMode(v, "osdBatteryWarn", "underlineBattGlow")
        }
        CollapsibleSection {
            expanded: root._battAlertMode !== "off"
            SliderRow {
                glyph: "󱟢"; label: "Alert below"
                value: ShellSettings.batteryLowThreshold
                min: 5; max: 50; step: 5
                displayValue: ShellSettings.batteryLowThreshold + "%"
                onChanged: (v) => ShellSettings.batteryLowThreshold = v
                glyphColor: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
            }
            HintText { text: "Escalates to critical at " + Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2)) + "%." }
        }
        ToggleRow {
            glyph: "󰂄"; label: "Fully-charged alert"
            enabled: ShellSettings.osdEnabled
            checked: ShellSettings.osdChargedNotify
            onToggled: ShellSettings.osdChargedNotify = !ShellSettings.osdChargedNotify
            dependsNote: "OSD off"
        }
    }

    SectionLabel { label: "CPU TEMPERATURE"; first: !Battery.available }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰔏"; label: "High temp alert"
            currentValue: root._tempAlertMode
            model: root._alertChipModel
            onChosen: (v) => root._setAlertMode(v, "osdTempWarn", "underlineTempGlow")
        }
        CollapsibleSection {
            expanded: root._tempAlertMode !== "off"
            SliderRow {
                glyph: "󰔏"; label: "Alert above"
                value: ShellSettings.tempHotThreshold
                min: 70; max: 105; step: 5
                displayValue: ShellSettings.tempHotThreshold + "°"
                onChanged: (v) => ShellSettings.tempHotThreshold = v
                glyphColor: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
            }
            HintText { text: "Escalates to critical at " + (ShellSettings.tempHotThreshold + 8) + "°." }
        }
    }

    CollapsibleSection {
        id: _alertsSection
        expanded: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn
        Loader {
            width: parent.width
            active: ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn || _alertsSection.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: Component {
                Column {
                    width: parent.width
                    SectionLabel { label: "ALERTS" }
                    SettingsCard {
                        ChoiceChipRow {
                            glyph: "󰀦"; label: "Auto-dismiss"
                            currentValue: ShellSettings.sysAlertTimeout
                            model: [
                                { value: 5000,  label: "5s"   },
                                { value: 10000, label: "10s"  },
                                { value: 20000, label: "20s"  },
                                { value: 0,     label: "Stay" }
                            ]
                            onChosen: (v) => ShellSettings.sysAlertTimeout = v
                        }
                    }
                }
            }
        }
    }
}
