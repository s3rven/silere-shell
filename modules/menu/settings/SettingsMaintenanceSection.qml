pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    property bool firstSection: true
    property bool animationActive: true
    property bool _optionalExpanded: false
    property bool _armed: false
    property real _armedAtMs: 0

    // reopening Diagnostics re-detects tools installed or removed while the shell is
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
        function onSettingsActiveChanged() { if (!MenuState.settingsActive) root._disarm() }
    }

    // Check on construction or refresh; cached pages never poll in the background.
    // Missing optional tools are useful information, but they are not a broken
    // shell. Keep them out of the attention count so Diagnostics does not read
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
                "Fonts", false, "interface", Theme.warning)
        else if (FontScan.scanned && FontScan.families.length === 0)
            add(attention, "󰈵", "Icon font missing",
                "Bar and menu icons may not render", "Choose font", false,
                "interface", Theme.warning)
        else if (FontScan.scanned && ShellSettings.fontFamily.length > 0
                 && FontScan.families.indexOf(ShellSettings.fontFamily) < 0)
            add(attention, "󰈵", "Chosen font unavailable",
                "Using " + Settings.font + " instead", "Choose font", false,
                "interface", Theme.warning)

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
        if (Settings.nightLightTool.length === 0) {
            if (ShellSettings.nightLightProvider === "auto")
                tool("󰖙", "Night light", Compositor.isHyprland ? "hyprsunset" : "wlsunset")
            else
                add(attention, "󰖙", "Night light unavailable",
                    "Selected program cannot run", "Choose", false, "interface", Theme.warning)
        }
        if (Settings.soundSettingsCommand.length === 0)
            tool("󰕾", "Sound settings", "pwvucontrol")
        if (!SystemTools.hasCava)              tool("󰝚", "Audio visualizer", "cava")
        if (!PowerProfiles.available)          tool("󰾅", "Power profiles", "power-profiles-daemon")
        if (Settings.lockCommand.length === 0) {
            if (ShellSettings.lockProvider === "auto")
                tool("󰌾", "Screen lock", Compositor.isHyprland ? "hyprlock" : "swaylock")
            else
                add(attention, "󰌾", "Screen lock unavailable",
                    ShellSettings.lockProvider === "custom" ? "Custom command is empty or invalid"
                        : "Selected program is not installed",
                    "Choose", false, "interface", Theme.warning)
        }
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
        return "No issues found"
    }
    readonly property string _healthDetail: {
        if (SystemTools.probeFailed) return SystemTools.lastError
        if (root._healthBusy) return "The last confirmed results stay visible while Silere checks again."
        if (root._attentionIssues.length > 0)
            return "Review the items below. Expand Optional features to see available add-ons."
        if (root._optionalIssues.length > 0)
            return "Expand Optional features to see packages you can add when you want them."
        return "All checked tools and integrations are available."
    }

    SectionLabel { label: "HEALTH"; first: root.firstSection }
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
            animationActive: root.animationActive && MenuState.settingsActive && !Idle.isIdle
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
                onActivated: {
                    if (modelData.a === "matugen") SystemTools.repairMatugen()
                    else if (modelData.a === "interface") MenuState.setSettingsSection("interface")
                }
            }
        }
        HintText {
            visible: root._attentionIssues.some(i => i.p === true)
            text: "The value on the right is the package or fallback involved."
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
            text: "Resets appearance, widget order, program choices, and other preferences. Wallpaper colors and notification history stay unchanged."
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
        ControlRow {
            glyph: "󰀻"
            title: "Optional features"
            status: root._optionalIssues.length + (root._optionalIssues.length === 1
                ? " add-on or check available" : " add-ons or checks available")
            expandable: true
            expanded: root._optionalExpanded
            onActivated: root._optionalExpanded = !root._optionalExpanded
            onExpandToggled: root._optionalExpanded = !root._optionalExpanded
        }
        CollapsibleSection {
            expanded: root._optionalExpanded
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
                text: "Install only the features you want. The value on the right names the package or integration involved."
            }
        }
    }
}
