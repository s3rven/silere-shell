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

    // the same size at uiScale 1.0; a surface fixed in px widens by what the type gained over it
    readonly property int fontSizeBase: Math.round(12 * root.fontScale)

    // the same measure at uiScale 1.0; row metrics grow past their design height only above it
    readonly property int capHeightBase: Math.ceil(_capBaseM.height)
    TextMetrics { id: _capBaseM; font.family: root.font; font.pixelSize: root.fontSizeBase; text: "M" }

    // small type steps floor so a lowered uiScale cannot push secondary text under legibility; sizes above body need no floor
    readonly property int fontLabel:   Math.max(9, fontSize - 1)
    readonly property int fontCaption: Math.max(9, fontSize - 2)
    readonly property int fontMicro:   Math.max(8, fontSize - 3)
    readonly property int fontTiny:    Math.max(8, fontSize - 4)

    readonly property int hPad: 14

    function lockProviderArgv(name: string): var {
        if (name === "hyprlock") return SystemTools.hasHyprlock ? ["hyprlock"] : []
        if (name === "swaylock") return SystemTools.hasSwaylock ? ["swaylock"] : []
        if (name === "gtklock")  return SystemTools.hasGtklock  ? ["gtklock"]  : []
        if (name === "loginctl") return SystemTools.hasLoginctl ? ["loginctl", "lock-session"] : []
        return []
    }

    // hyprlock leads only where it is native; elsewhere the wlroots locker goes first
    readonly property var _lockOrder: Compositor.isHyprland
        ? ["hyprlock", "swaylock", "gtklock", "loginctl"]
        : ["swaylock", "gtklock", "hyprlock", "loginctl"]

    readonly property string autoLockProvider: {
        const order = root._lockOrder
        for (let i = 0; i < order.length; i++)
            if (root.lockProviderArgv(order[i]).length > 0) return order[i]
        return ""
    }

    function nightLightProviderArgv(name: string, temp: int): var {
        const t = Math.max(1000, Math.min(20000, Math.round(temp)))
        if (name === "hyprsunset")
            return Compositor.isHyprland && SystemTools.hasHyprsunset
                ? ["hyprsunset", "-t", String(t)] : []
        // wlsunset interpolates between an unequal day and night pair and exits on an equal
        // one, so hold a value with a day that spans the clock and sits one step above night
        if (name === "wlsunset") {
            const day = Math.max(1001, t)
            return SystemTools.hasWlsunset
                ? ["wlsunset", "-T", String(day), "-t", String(day - 1),
                   "-S", "00:00", "-s", "23:59", "-d", "1"] : []
        }
        return []
    }

    // hyprsunset needs a hyprland-only protocol
    readonly property string autoNightLightProvider:
        Compositor.isHyprland && SystemTools.hasHyprsunset ? "hyprsunset"
        : SystemTools.hasWlsunset ? "wlsunset" : ""

    readonly property string nightLightTool: {
        const choice = ShellSettings.nightLightProvider
        if (choice === "auto") return root.autoNightLightProvider
        return root.nightLightProviderArgv(choice, 4000).length > 0 ? choice : ""
    }

    function nightLightCommand(temp: int): var {
        return root.nightLightProviderArgv(root.nightLightTool, temp)
    }

    // per-app routing is a mixer's job, not a bar's
    readonly property list<string> soundSettingsCommand: SystemTools.hasPwvucontrol
        ? ["pwvucontrol"] : SystemTools.hasPavucontrol ? ["pavucontrol"] : []

    readonly property list<string> customLockCommand: root.splitCommand(ShellSettings.lockCommandCustom)

    // shell-style words with no shell: quotes group, a backslash escapes, an unclosed quote yields nothing
    function splitCommand(raw): var {
        const text = String(raw ?? "")
        const out = []
        let word = "", open = false, quote = ""
        for (let i = 0; i < text.length; i++) {
            const c = text[i]
            if (quote === "'") {
                if (c === "'") quote = ""
                else word += c
            } else if (quote === "\"") {
                if (c === "\"") quote = ""
                else if (c === "\\" && (text[i + 1] === "\"" || text[i + 1] === "\\")) word += text[++i]
                else word += c
            } else if (c === "'" || c === "\"") {
                quote = c
                open = true
            } else if (c === "\\" && i + 1 < text.length) {
                word += text[++i]
                open = true
            } else if (/\s/.test(c)) {
                if (open) out.push(word)
                word = ""
                open = false
            } else {
                word += c
                open = true
            }
        }
        if (quote.length > 0) return []
        if (open) out.push(word)
        return out
    }

    // a named provider that is not installed stays empty: the lock button disables and
    // Maintenance names it, rather than silently locking with a different program
    readonly property list<string> lockCommand: {
        const choice = ShellSettings.lockProvider
        if (choice === "custom") return root.customLockCommand
        if (choice !== "auto") return root.lockProviderArgv(choice)
        return root.lockProviderArgv(root.autoLockProvider)
    }
    readonly property list<string> suspendCommand: SystemTools.hasSystemctl ? ["systemctl", "suspend"]
        : SystemTools.hasLoginctl ? ["loginctl", "suspend"] : []
    readonly property list<string> rebootCommand: SystemTools.hasSystemctl ? ["systemctl", "reboot"]
        : SystemTools.hasLoginctl ? ["loginctl", "reboot"] : []
    readonly property list<string> poweroffCommand: SystemTools.hasSystemctl ? ["systemctl", "poweroff"]
        : SystemTools.hasLoginctl ? ["loginctl", "poweroff"] : []
}
