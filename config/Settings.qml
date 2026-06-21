pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property string font: "JetBrainsMono Nerd Font, monospace"
    // Base 12px scaled by the user's UI scale (System → UI scale: 80-115%).
    // 115% resolves to 14px: the largest size that still fits the bar's 24px
    // pills and the shared menu rows without clipping.
    readonly property int fontSize: Math.round(12 * ShellSettings.uiScale)
    readonly property int hPad: 14

    // Force Lua dispatch API (hl.dsp.focus). Auto-detected from the Hyprland config under XDG_CONFIG_HOME;
    // set true only if auto-detection misses your Lua setup.
    readonly property bool hyprLuaConfig: false

    readonly property list<string> lockCommand: ["hyprlock"]
    readonly property list<string> suspendCommand: ["systemctl", "suspend"]
    readonly property list<string> rebootCommand: ["systemctl", "reboot"]
    readonly property list<string> poweroffCommand: ["systemctl", "poweroff"]
}
