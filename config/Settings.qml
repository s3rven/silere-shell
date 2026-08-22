pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    id: root

    // exact family only: Qt 6 passes this verbatim, a comma list trips fontconfig 2.18's family guesser
    readonly property string defaultFont: "JetBrainsMono Nerd Font"
    readonly property string font: {
        const installed = FontScan.families
        const chosen = ShellSettings.fontFamily
        // an empty scan means fc-list is absent or still running, not that the font is gone
        if (chosen.length > 0 && (installed.length === 0 || installed.indexOf(chosen) >= 0))
            return chosen
        // the default is not installed everywhere; without a Nerd Font the bar is all tofu
        if (installed.length === 0 || installed.indexOf(root.defaultFont) >= 0) return root.defaultFont
        return installed[0]
    }
    // normalize on xHeight, not line height (the Meslo LG variants differ only in line gap); 0.55 = JetBrainsMono, so the default scales at 1.0
    readonly property real fontScale: Math.max(0.85, Math.min(1.2, 0.55 / Math.max(0.3, _fm.xHeight / 100)))
    readonly property int fontSize: Math.round(12 * ShellSettings.uiScale * fontScale)
    readonly property int iconSize: Math.round(12 * ShellSettings.uiScale)

    FontMetrics { id: _fm; font.family: root.font; font.pixelSize: 100 }

    readonly property int capHeight: Math.ceil(_capM.height)
    TextMetrics { id: _capM; font.family: root.font; font.pixelSize: root.fontSize; text: "M" }

    // the same measure at uiScale 1.0; row metrics grow past their design height only above it
    readonly property int capHeightBase: Math.ceil(_capBaseM.height)
    TextMetrics { id: _capBaseM; font.family: root.font; font.pixelSize: Math.round(12 * root.fontScale); text: "M" }

    // small type steps floor so a lowered uiScale cannot push secondary text under legibility; sizes above body need no floor
    readonly property int fontLabel:   Math.max(9, fontSize - 1)
    readonly property int fontCaption: Math.max(9, fontSize - 2)
    readonly property int fontMicro:   Math.max(8, fontSize - 3)
    readonly property int fontTiny:    Math.max(8, fontSize - 4)

    readonly property int hPad: 14

    readonly property list<string> lockCommand: SystemTools.hasHyprlock ? ["hyprlock"]
        : SystemTools.hasLoginctl ? ["loginctl", "lock-session"] : []
    readonly property list<string> suspendCommand: SystemTools.hasSystemctl ? ["systemctl", "suspend"]
        : SystemTools.hasLoginctl ? ["loginctl", "suspend"] : []
    readonly property list<string> rebootCommand: SystemTools.hasSystemctl ? ["systemctl", "reboot"]
        : SystemTools.hasLoginctl ? ["loginctl", "reboot"] : []
    readonly property list<string> poweroffCommand: SystemTools.hasSystemctl ? ["systemctl", "poweroff"]
        : SystemTools.hasLoginctl ? ["loginctl", "poweroff"] : []
}
