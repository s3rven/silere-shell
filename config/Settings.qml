pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    id: root

    // exact family only: Qt 6 passes this verbatim, a comma list trips fontconfig 2.18's family guesser
    readonly property string font: ShellSettings.fontFamily.length > 0 ? ShellSettings.fontFamily : "JetBrainsMono Nerd Font"
    // families render different optical sizes at equal px (Fantasque ≈ 10% shorter) — normalize on
    // xHeight, not line height: the Meslo LG variants differ only in line gap, not glyph size.
    // 0.55 = JetBrainsMono's xHeight/px, so the default family scales at exactly 1.0.
    readonly property real fontScale: Math.max(0.85, Math.min(1.2, 0.55 / Math.max(0.3, _fm.xHeight / 100)))
    // base 12px × UI scale (80-115%). 115%→14px: largest that still fits the bar's 24px pills and menu rows without clipping.
    readonly property int fontSize: Math.round(12 * ShellSettings.uiScale * fontScale)
    // Nerd icons are the same artwork in every family — size them from the unscaled base so a font switch never resizes or shifts them
    readonly property int iconSize: Math.round(12 * ShellSettings.uiScale)

    FontMetrics { id: _fm; font.family: root.font; font.pixelSize: 100 }

    // ink height of "M" at the bar size; shared so every separator doesn't shape its own glyph
    readonly property int capHeight: Math.ceil(_capM.height)
    TextMetrics { id: _capM; font.family: root.font; font.pixelSize: root.fontSize; text: "M" }

    readonly property int hPad: 14

    // force Lua dispatch API (hl.dsp.focus); auto-detected from the Hyprland config, set true only if detection misses your setup
    readonly property bool hyprLuaConfig: false

    readonly property list<string> lockCommand: ["hyprlock"]
    readonly property list<string> suspendCommand: SystemTools.hasSystemctl ? ["systemctl", "suspend"]
        : SystemTools.hasLoginctl ? ["loginctl", "suspend"] : []
    readonly property list<string> rebootCommand: SystemTools.hasSystemctl ? ["systemctl", "reboot"]
        : SystemTools.hasLoginctl ? ["loginctl", "reboot"] : []
    readonly property list<string> poweroffCommand: SystemTools.hasSystemctl ? ["systemctl", "poweroff"]
        : SystemTools.hasLoginctl ? ["loginctl", "poweroff"] : []
}
