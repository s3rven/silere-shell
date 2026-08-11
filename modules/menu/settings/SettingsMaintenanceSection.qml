import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    property bool _armed: false
    property real _armedAtMs: 0

    function _disarm(): void {
        root._armed = false
        _armTimer.stop()
    }

    Timer {
        id: _armTimer
        interval: 3000
        onTriggered: root._armed = false
    }

    Connections {
        target: MenuState
        function onSettingsSectionChanged() { root._disarm() }
        function onOpenChanged() { if (!MenuState.open) root._disarm() }
    }

    SectionLabel { label: "DEFAULTS"; first: true }
    SettingsCard {
        ControlRow {
            glyph: "󰦛"
            title: root._armed ? "Confirm reset" : "Restore defaults"
            status: ShellSettings.modifiedCount > 0
                ? ShellSettings.modifiedCount + (ShellSettings.modifiedCount === 1
                    ? " setting changed" : " settings changed")
                : "Everything is at its default"
            valueText: root._armed ? "Tap again" : ""
            accentColor: root._armed ? Theme.error : Theme.accent
            active: root._armed
            available: ShellSettings.modifiedCount > 0
            onActivated: {
                if (root._armed) {
                    // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
                    if (Date.now() - root._armedAtMs < Metrics.confirmGuardMs) return
                    root._disarm()
                    ShellSettings.resetToDefaults()
                } else {
                    root._armed = true
                    root._armedAtMs = Date.now()
                    _armTimer.restart()
                }
            }
        }
        HintText {
            text: "Backs up current settings before resetting. Wallpaper colors and calendar marks stay."
        }
    }

    // reads flags SystemTools and FontScan already probed once at startup: no new spawn, no
    // polling, and the whole section only instantiates while it is the open page
    readonly property var _issues: {
        const out = []
        if (!SystemTools.ready) return out

        // a dead font tofus the bar AND the menu that would fix it, so it leads
        if (!SystemTools.hasFcList)
            out.push({ g: "󰈵", n: "Font check", s: "Cannot verify the interface font", v: "fontconfig" })
        else if (FontScan.scanned && FontScan.families.length === 0)
            out.push({ g: "󰈵", n: "Icon font", s: "No Nerd Font installed — bar icons cannot render", v: "nerd-fonts" })
        else if (FontScan.scanned && ShellSettings.fontFamily.length > 0
                 && FontScan.families.indexOf(ShellSettings.fontFamily) < 0)
            out.push({ g: "󰈵", n: "Chosen font", s: "“" + ShellSettings.fontFamily + "” is gone; using " + Settings.font, v: "fallback" })

        const tool = (g, n, v) => out.push({ g: g, n: n, s: "Hidden until this is installed", v: v })
        if (!SystemTools.hasBrightnessctl)     tool("󰃟", "Brightness control", "brightnessctl")
        if (!SystemTools.hasHyprsunset)        tool("󰖙", "Night light", "hyprsunset")
        if (!SystemTools.hasCava)              tool("󰝚", "Audio visualizer", "cava")
        if (!SystemTools.hasPowerProfilesCtl)  tool("󰾅", "Power profiles", "power-profiles-daemon")
        if (!SystemTools.hasHyprlock)          tool("󰌾", "Screen lock", "hyprlock")
        if (!SystemTools.hasCheckupdates && !SystemTools.hasParu && !SystemTools.hasYay
                && SystemTools.packageFamily === "pacman")
            tool("󰚰", "Update checks", "pacman-contrib")
        // the warnings page stays visible and settable without notify-send, so this one is inert rather than hidden
        if (!SystemTools.hasNotifySend)
            out.push({ g: "󰂚", n: "System alerts", s: "Battery and temperature warnings cannot be sent", v: "libnotify" })
        return out
    }

    SectionLabel { label: "HEALTH" }
    SettingsCard {
        ControlRow {
            visible: SystemTools.ready && root._issues.length === 0
            glyph: "󰗠"
            title: "All optional tools found"
            status: "No features are hidden"
            passive: true
        }
        ControlRow {
            visible: !SystemTools.ready
            glyph: "󰋼"
            title: "Checking optional tools…"
            passive: true
        }
        Repeater {
            model: root._issues
            ControlRow {
                required property var modelData
                glyph: modelData.g
                title: modelData.n
                status: modelData.s
                valueText: modelData.v
                passive: true
            }
        }
        HintText {
            visible: root._issues.length > 0
            text: "Install the listed package to enable its feature."
        }
    }
}
