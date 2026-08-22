import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

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
        ShellSettings.batch(() => {
            ShellSettings[osdKey] = (v === "osd" || v === "both")
            ShellSettings[glowKey] = (v === "glow" || v === "both")
        })
    }

    readonly property string _battAlertMode: root._alertMode(
        ShellSettings.osdBatteryWarn, ShellSettings.underlineBattGlow)
    readonly property string _tempAlertMode: root._alertMode(
        ShellSettings.osdTempWarn, ShellSettings.underlineTempGlow)
    readonly property bool _batteryDesktopAlert:
        Battery.available && ShellSettings.osdBatteryWarn
    readonly property bool _tempDesktopAlert:
        !CpuTemp.sensorMissing && ShellSettings.osdTempWarn
    readonly property bool _desktopAlertsEnabled:
        root._batteryDesktopAlert || root._tempDesktopAlert
    readonly property bool _hardwareStatusVisible:
        !Battery.available && CpuTemp.sensorMissing

    readonly property var _alertChipModel: ShellSettings.underlineGlow
        ? [
            { value: "off",  label: "Off"  },
            { value: "osd",  label: "Alert" },
            { value: "glow", label: "Glow" },
            { value: "both", label: "Both" }
        ]
        : [
            { value: "off", label: "Off" },
            { value: "osd", label: "Alert" }
          ]

    SectionLabel { label: "BATTERY"; first: true; visible: Battery.available }
    SettingsCard {
        visible: Battery.available
        ChoiceChipRow {
            glyph: "󱃍"; label: "Low battery warning"
            currentValue: root._battAlertMode
            model: root._alertChipModel
            onChosen: (v) => root._setAlertMode(v, "osdBatteryWarn", "underlineBattGlow")
        }
        // ungated: the power rail label, the vitals strip and the battery colour read this
        // threshold whether or not either warning is switched on
        SliderRow {
            glyph: "󱃍"; label: "Low below"
            key: "batteryLowThreshold"
            step: 5
            displayValue: ShellSettings.batteryLowThreshold + "%"
            glyphColor: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
        }
        HintText { text: "Escalates to critical at " + Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2)) + "%." }
        ToggleRow {
            glyph: "󰂄"; label: "Fully charged alert"
            enabled: ShellSettings.osdEnabled
            key: "osdChargedNotify"
            dependsNote: "OSD off"
        }
    }

    SectionLabel {
        label: "CPU TEMPERATURE"
        first: !Battery.available
        visible: !CpuTemp.sensorMissing
    }
    SettingsCard {
        visible: !CpuTemp.sensorMissing
        ChoiceChipRow {
            glyph: "󰔏"; label: "High temperature warning"
            currentValue: root._tempAlertMode
            model: root._alertChipModel
            onChosen: (v) => root._setAlertMode(v, "osdTempWarn", "underlineTempGlow")
        }
        SliderRow {
            glyph: "󰔏"; label: "Hot above"
            key: "tempHotThreshold"
            step: 5
            displayValue: ShellSettings.tempHotThreshold + "°"
            glyphColor: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
        }
        HintText { text: "Escalates to critical at " + (ShellSettings.tempHotThreshold + 8) + "°." }
    }

    SectionLabel {
        label: "HARDWARE"
        first: true
        visible: root._hardwareStatusVisible
    }
    SettingsCard {
        visible: root._hardwareStatusVisible
        ControlRow {
            glyph: "󰋼"
            title: "No alert hardware found"
            status: "Battery and temperature alerts stay hidden"
            passive: true
        }
    }

    CollapsibleSection {
        id: _alertsSection
        expanded: root._desktopAlertsEnabled
        Loader {
            width: parent.width
            active: root._desktopAlertsEnabled || _alertsSection.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: Component {
                Column {
                    width: parent.width
                    SectionLabel { label: "DESKTOP NOTIFICATIONS" }
                    SettingsCard {
                        SelectRow {
                            glyph: "󰔛"; label: "Dismiss after"
                            currentValue: ShellSettings.sysAlertTimeout
                            fallbackLabel: ShellSettings.sysAlertTimeout === 0
                                ? "Stay" : (ShellSettings.sysAlertTimeout / 1000) + "s"
                            model: [
                                { value: 5000,  label: "5s"   },
                                { value: 10000, label: "10s"  },
                                { value: 20000, label: "20s"  },
                                { value: 0,     label: "Stay" }
                            ]
                            onChosen: (v) => ShellSettings.sysAlertTimeout = v
                        }
                        HintText {
                            visible: SystemTools.ready && !SystemTools.hasNotifySend
                            text: "Desktop notifications need libnotify."
                        }
                        HintText {
                            text: ShellSettings.osdEnabled
                                ? "Alert also appears in the shell OSD."
                                : "Enable the global OSD to also show the shell alert."
                        }
                    }
                }
            }
        }
    }
}
