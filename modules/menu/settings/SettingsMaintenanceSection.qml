pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    readonly property var _nightLightChoices: {
        const auto = Settings.autoNightLightProvider
        const out = [{ value: "auto",
            label: auto.length > 0 ? "Automatic (" + auto + ")" : "Automatic (none found)" }]
        const named = [
            { value: "hyprsunset", label: "hyprsunset",
              ok: Compositor.isHyprland && SystemTools.hasHyprsunset },
            { value: "wlsunset",   label: "wlsunset",   ok: SystemTools.hasWlsunset   }
        ]
        for (let i = 0; i < named.length; i++) {
            if (named[i].value === "hyprsunset" && !Compositor.isHyprland) continue
            out.push({ value: named[i].value,
                label: named[i].ok ? named[i].label : named[i].label + " (not installed)" })
        }
        return out
    }

    readonly property var _lockChoices: {
        const auto = Settings.autoLockProvider
        const out = [{ value: "auto",
            label: auto.length > 0 ? "Automatic (" + auto + ")" : "Automatic (none found)" }]
        const named = [
            { value: "hyprlock", label: "hyprlock",             ok: SystemTools.hasHyprlock },
            { value: "swaylock", label: "swaylock",             ok: SystemTools.hasSwaylock },
            { value: "gtklock",  label: "gtklock",              ok: SystemTools.hasGtklock  },
            { value: "loginctl", label: "loginctl lock-session", ok: SystemTools.hasLoginctl }
        ]
        for (let i = 0; i < named.length; i++)
            out.push({ value: named[i].value,
                label: named[i].ok ? named[i].label : named[i].label + " (not installed)" })
        out.push({ value: "custom", label: "Custom command" })
        return out
    }

    property bool _armed: false
    property real _armedAtMs: 0

    // reopening Maintenance re-detects tools installed or removed while the shell is
    // running, but a recent answer still stands; Refresh on the page forces one
    Component.onCompleted: {
        SystemTools.refreshIfStale(60000)
        FontScan.requestScan()
    }

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

    // the whole section only instantiates while it is the open page; the probe runs once on entry and never polls in the background
    // Missing optional tools are useful information, but they are not a broken
    // shell. Keep them out of the attention count so Maintenance does not read
    // like an error page on a deliberately minimal installation.
    readonly property var _health: {
        const attention = []
        const optional = []
        if (!SystemTools.ready || SystemTools.probeFailed)
            return { attention: attention, optional: optional }

        const add = (target, g, n, s, v, p, a, c) => target.push({
            g: g, n: n, s: s, v: v, p: p === true,
            a: a || "", c: c || "transparent"
        })

        // a dead font tofus the bar AND the menu that would fix it, so it leads
        if (!SystemTools.hasFcList)
            add(optional, "󰈵", "Font verification",
                "Cannot check installed fonts", "fontconfig", true)
        else if (FontScan.lastError.length > 0)
            add(attention, "󰈵", "Font check", FontScan.lastError,
                "fc-list", false, "", Theme.warning)
        else if (FontScan.scanned && FontScan.families.length === 0)
            add(attention, "󰈵", "Icon font missing",
                "Bar and menu icons may not render", "nerd-fonts", true,
                "", Theme.warning)
        else if (FontScan.scanned && ShellSettings.fontFamily.length > 0
                 && FontScan.families.indexOf(ShellSettings.fontFamily) < 0)
            add(attention, "󰈵", "Chosen font unavailable",
                "Using " + Settings.font + " instead", "Fallback", false,
                "", Theme.warning)

        // wallpaper theming degrades instead of hiding, so it reads as working while the palette silently stays bundled — both causes need naming
        if (!SystemTools.hasMatugen)
            add(optional, "󰉦", "Wallpaper theming",
                MatugenTheme.usingFallback ? "Wallpaper colors are unavailable"
                    : "Last palette stays; sync stops",
                "matugen", true)
        else if (MatugenTheme.paletteStale)
            add(attention, "󰉦", "Wallpaper palette unreadable",
                "Showing the last colors that loaded", "Template", false,
                "", Theme.warning)
        else if (MatugenTheme.usingFallback) {
            const repaired = SystemTools.matugenRepairState === "done"
            add(repaired ? optional : attention, "󰉦", "Wallpaper palette",
                SystemTools.matugenRepairState === "working" ? "Rewiring Matugen…"
                    : SystemTools.matugenRepairState === "done" ? "Rewired — colors follow your next wallpaper change"
                    : SystemTools.matugenRepairState === "failed" ? "Could not rewire; run scripts/install.sh"
                    : "Matugen has not written one yet",
                SystemTools.matugenRepairState === "working" ? "" : "Repair",
                false, SystemTools.matugenRepairState === "working" ? "" : "matugen",
                SystemTools.matugenRepairState === "done" ? Theme.success : Theme.warning)
        }

        if (Notifications.storeError.length > 0)
            add(attention, "󰂚", "Notification history",
                Notifications.storeError, "notifications.json", false, "", Theme.warning)

        if (NotifWatch.conflict.length > 0)
            add(attention, "󰂛", "Notifications blocked",
                "Another daemon owns notifications", NotifWatch.conflict, false,
                "", Theme.warning)

        const tool = (g, n, v) => add(optional, g, n,
            "Not installed", v, true)
        if (!SystemTools.hasBrightnessctl)     tool("󰃟", "Brightness control", "brightnessctl")
        if (Settings.autoNightLightProvider.length === 0)
            tool("󰖙", "Night light", Compositor.isHyprland ? "hyprsunset" : "wlsunset")
        if (Settings.soundSettingsCommand.length === 0)
            tool("󰕾", "Sound settings", "pwvucontrol")
        if (!SystemTools.hasCava)              tool("󰝚", "Audio visualizer", "cava")
        if (!PowerProfiles.available)          tool("󰾅", "Power profiles", "power-profiles-daemon")
        if (Settings.lockCommand.length === 0)  tool("󰌾", "Screen lock", "hyprlock")
        if (!SystemTools.hasCheckupdates && !SystemTools.hasParu && !SystemTools.hasYay
                && SystemTools.packageFamily === "pacman")
            tool("󰚰", "Update checks", "pacman-contrib")
        // the warnings page stays visible and settable without notify-send, so this one is inert rather than hidden
        if (!SystemTools.hasNotifySend) {
            const target = ShellSettings.osdBatteryWarn || ShellSettings.osdTempWarn
                ? attention : optional
            add(target, "󰂚", "System alerts",
                target === attention
                    ? "Warnings cannot be delivered"
                    : "Not installed",
                "libnotify", true, "",
                target === attention ? Theme.warning : "transparent")
        }
        return { attention: attention, optional: optional }
    }
    readonly property var _attentionIssues: root._health.attention
    readonly property var _optionalIssues: root._health.optional
    readonly property bool _healthBusy: !SystemTools.ready || SystemTools.checking
        || FontScan.scanning
    readonly property string _healthStatus: {
        if (!SystemTools.ready) return "Checking installed features…"
        if (SystemTools.checking || FontScan.scanning) return "Refreshing availability…"
        if (SystemTools.probeFailed) return "The feature check could not finish"
        if (root._attentionIssues.length > 0)
            return root._attentionIssues.length
                + (root._attentionIssues.length === 1
                    ? " item needs attention" : " items need attention")
        if (root._optionalIssues.length > 0)
            return root._optionalIssues.length
                + (root._optionalIssues.length === 1
                    ? " optional feature missing" : " optional features missing")
        return "Installed features are ready"
    }
    readonly property string _healthDetail: {
        if (SystemTools.probeFailed) return SystemTools.lastError
        if (root._healthBusy) return "The last confirmed results stay visible while Silere checks again."
        if (root._attentionIssues.length > 0)
            return "Review the items below. Optional packages are listed separately."
        if (root._optionalIssues.length > 0)
            return "Silere is healthy. Install an optional package only if you want that feature."
        return "All checked tools and integrations are available."
    }

    SectionLabel { label: "HEALTH"; first: true }
    SettingsCard {
        UpdateStatusCard {
            glyph: root._healthBusy ? "󰑐"
                : SystemTools.probeFailed ? "󰀦"
                : root._attentionIssues.length > 0 ? "󰀪" : "󰄬"
            title: "Feature readiness"
            status: root._healthStatus
            detail: root._healthDetail
            detailError: SystemTools.probeFailed
            statusColor: SystemTools.probeFailed ? Theme.error
                : root._attentionIssues.length > 0 ? Theme.warning
                : root._healthBusy ? Theme.accent : Theme.success
            busy: root._healthBusy
            animationActive: MenuState.settingsActive && !Idle.isIdle
            primaryLabel: root._healthBusy ? "Refreshing" : "Refresh"
            primaryGlyph: "󰑐"
            primaryEnabled: !root._healthBusy
            onPrimaryTriggered: {
                SystemTools.refresh()
                FontScan.scan(true)
            }
        }
    }

    SectionLabel {
        visible: SystemTools.ready && !SystemTools.probeFailed
            && root._attentionIssues.length > 0
        label: "NEEDS ATTENTION"
    }
    SettingsCard {
        visible: SystemTools.ready && !SystemTools.probeFailed
            && root._attentionIssues.length > 0
        Repeater {
            model: root._attentionIssues
            ControlRow {
                required property var modelData
                glyph: modelData.g
                title: modelData.n
                status: modelData.s
                valueText: modelData.v
                statusColor: modelData.c
                passive: !modelData.a
                valueIsAction: modelData.a.length > 0
                onActivated: if (modelData.a === "matugen") SystemTools.repairMatugen()
            }
        }
        HintText {
            visible: root._attentionIssues.some(i => i.p === true)
            text: "The value on the right is the package or fallback involved."
        }
    }

    SectionLabel {
        visible: SystemTools.ready && !SystemTools.probeFailed
            && root._optionalIssues.length > 0
        label: "OPTIONAL FEATURES"
    }
    SettingsCard {
        visible: SystemTools.ready && !SystemTools.probeFailed
            && root._optionalIssues.length > 0
        Repeater {
            model: root._optionalIssues
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
            text: "These are add-ons or informational checks, not shell failures. Add only the features you want."
        }
    }

    SectionLabel { label: "PROGRAMS" }
    SettingsCard {
        SelectRow {
            glyph: "󰌾"; label: "Screen lock"
            currentValue: ShellSettings.lockProvider
            model: root._lockChoices
            onChosen: (v) => ShellSettings.lockProvider = v
        }
        HintText {
            visible: ShellSettings.lockProvider === "custom"
                && Settings.customLockCommand.length === 0
            text: "No command set yet. Run: silere ipc settings set lockCommandCustom \"swaylock -f\""
        }
        HintText {
            visible: ShellSettings.lockProvider !== "custom"
                && Settings.lockCommand.length === 0
            text: "The chosen lock program is not installed, so the lock action stays off."
        }
        SelectRow {
            glyph: "󰖙"; label: "Night light"
            currentValue: ShellSettings.nightLightProvider
            model: root._nightLightChoices
            onChosen: (v) => ShellSettings.nightLightProvider = v
        }
        HintText {
            visible: Settings.nightLightTool.length === 0
            text: Compositor.isHyprland
                ? "Neither program is installed, so night light stays off."
                : "hyprsunset needs Hyprland. On this compositor install wlsunset instead."
        }
    }

    SectionLabel { label: "RECOVERY" }
    SettingsCard {
        ControlRow {
            glyph: "󰦛"
            title: root._armed ? "Confirm restore" : "Restore default settings"
            status: ShellSettings.modifiedCount > 0
                ? ShellSettings.modifiedCount + (ShellSettings.modifiedCount === 1
                    ? " setting will be reset" : " settings will be reset")
                : "No changed settings to restore"
            valueText: root._armed ? "Tap again" : ""
            accentColor: root._armed ? Theme.error : Theme.accent
            statusColor: root._armed ? Theme.error : "transparent"
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
            text: "Wallpaper colors and calendar marks stay unchanged."
        }
    }
}
