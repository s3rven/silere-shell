pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property string font: "JetBrainsMono Nerd Font, monospace"
    // Base 12px scaled by the user's UI scale (Appearance → UI scale: 80-100%).
    // Every glyph and label reads this, so it scales the whole shell down for a more
    // compact bar/menu. Down-only, so it never risks clipping text in fixed boxes.
    readonly property int fontSize: Math.round(12 * ShellSettings.uiScale)
    readonly property int hPad: 14

    // Force Lua dispatch API (hl.dsp.focus). Auto-detected from ~/.config/hypr/hyprland.lua;
    // set true only if auto-detection misses your Lua setup.
    readonly property bool hyprLuaConfig: false

    readonly property list<string> lockCommand: ["hyprlock"]
    readonly property list<string> suspendCommand: ["systemctl", "suspend"]
    readonly property list<string> rebootCommand: ["systemctl", "reboot"]
    readonly property list<string> poweroffCommand: ["systemctl", "poweroff"]
}
