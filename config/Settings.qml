pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property string font: "JetBrainsMono Nerd Font, monospace"
    // base 12px × UI scale (80-115%). 115%→14px: largest that still fits the bar's 24px pills and menu rows without clipping.
    readonly property int fontSize: Math.round(12 * ShellSettings.uiScale)
    readonly property int hPad: 14

    // force Lua dispatch API (hl.dsp.focus); auto-detected from the Hyprland config, set true only if detection misses your setup
    readonly property bool hyprLuaConfig: false

    readonly property list<string> lockCommand: ["hyprlock"]
    readonly property list<string> suspendCommand: ["systemctl", "suspend"]
    readonly property list<string> rebootCommand: ["systemctl", "reboot"]
    readonly property list<string> poweroffCommand: ["systemctl", "poweroff"]
}
