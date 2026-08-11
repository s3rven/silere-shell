pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool open:    false
    property real anchorX: 10
    property QtObject anchorSource: null
    property ShellScreen triggerScreen: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }
    onAnchorSourceChanged: if (open && anchorSource === null) close()
    readonly property int homeTab: 0
    readonly property int settingsTab: 1
    readonly property int recentTab: 2
    property int _activeTab: homeTab
    readonly property int activeTab: _activeTab
    readonly property bool homeActive: open && activeTab === homeTab
    readonly property bool settingsActive: open && activeTab === settingsTab

    property string settingsSection: "theme"

    // Order by user impact and frequency: global appearance first, daily bar
    // surfaces next, then feedback; operational and recovery tools stay last.
    readonly property var settingsTree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme",
              description: "Colors, accent, and outlines" },
            { glyph: "󰍉", label: "Interface", section: "interface",
              description: "Font, scale, contrast, motion, and displays" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface",
              description: "Bar position, size, and shape" },
            { glyph: "󰍴", label: "Underline", section: "underline",
              description: "Line and event glow" },
            { glyph: "󰻂", label: "Spacing",   section: "separators",
              description: "Gaps and dividers" }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Order & visibility", section: "widgets",
              description: "Choose and reorder bar widgets" },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces",
              description: "Markers, labels, and app icons" },
            { glyph: "󰅐", label: "Clock",      section: "clock",
              description: "Date and time" },
            { glyph: "󰝚", label: "Media",      section: "media",
              description: "Track details and visualizer" },
            { glyph: "󰈈", label: "Indicators", section: "indicators",
              description: "Titles, status, and hover" }
        ]},
        { glyph: "󰂚", label: "Feedback", children: [
            { glyph: "󰂚", label: "Notifications", section: "popups",
              description: "Position, timeout, and quiet hours" },
            { glyph: "󱀅", label: "OSD",    section: "osd",
              description: "Volume and brightness feedback" },
            { glyph: "󰀦", label: "Alerts", section: "warnings",
              description: "Battery and temperature limits" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰚰", label: "Updates", section: "updates",
              description: "Shell releases and system packages" },
            { glyph: "󰦛", label: "Maintenance", section: "maintenance",
              description: "Defaults and dependencies" }
        ]}
    ]

    readonly property var _flatSections: {
        const out = []
        for (let i = 0; i < settingsTree.length; i++) {
            const it = settingsTree[i]
            if (it.children) for (let j = 0; j < it.children.length; j++) out.push(it.children[j].section)
            else out.push(it.section)
        }
        return out
    }

    function setSettingsSection(s: string): void {
        const next = root._flatSections.indexOf(s) >= 0 ? s : "theme"
        if (next !== settingsSection) settingsSection = next
    }

    signal tabRequested(int index)

    function _validTab(index: int): int {
        return Math.max(homeTab, Math.min(recentTab, index))
    }

    function selectTab(index: int): int {
        const tab = root._validTab(index)
        if (root._activeTab !== tab) root._activeTab = tab
        return tab
    }

    function toggleAt(x: real, screen, source): void {
        if (open) {
            close()
            return
        }
        anchorX = x
        anchorSource = source ?? null
        triggerScreen = screen ?? null
        _activeTab = homeTab
        open = true
    }
    function close(): void {
        // open first: clearing anchorSource while open re-enters close() through its handler
        if (open) open = false
        triggerScreen = null
        anchorSource = null
    }
    function showTab(index: int): void {
        const tab = selectTab(index)
        // set before opening: the lazy surface can't catch a pre-creation signal
        if (!open) open = true
        tabRequested(tab)
    }

    IpcHandler {
        target: "menu"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.triggerScreen = null
            root.anchorSource = null
            root._activeTab = root.homeTab
            root.open = true
        }
        function close(): void { root.close() }
        function tab(index: int): string {
            if (index < root.homeTab || index > root.recentTab)
                return "unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (recent)"
            root.triggerScreen = null
            root.anchorSource = null
            root.showTab(index)
            return "ok"
        }
        // keep `section: "` out of any literal below: ci-lint harvests nav entries by that pattern
        function settings(name: string): string {
            if (root._flatSections.indexOf(name) < 0)
                return "unknown settings page '" + name + "'; valid: " + root._flatSections.join(", ")
            root.triggerScreen = null
            root.anchorSource = null
            root.setSettingsSection(name)
            root.showTab(root.settingsTab)
            return "ok"
        }
    }
}
