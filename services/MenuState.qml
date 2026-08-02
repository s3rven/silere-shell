pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool open:    false
    property real anchorX: 10
    property ShellScreen triggerScreen: null
    readonly property int homeTab: 0
    readonly property int settingsTab: 1
    readonly property int recentTab: 2
    property int _activeTab: homeTab
    readonly property int activeTab: _activeTab
    readonly property bool homeActive: open && activeTab === homeTab
    readonly property bool settingsActive: open && activeTab === settingsTab
    readonly property bool recentActive: open && activeTab === recentTab

    property string settingsSection: "theme"

    readonly property var settingsTree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme",
              description: "Palette, accent, contrast, and outlines" },
            { glyph: "󰖙", label: "Night light", section: "nightlight",
              description: "Warmer display color and automatic timing" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface",
              description: "Position, size, shape, and surface behavior" },
            { glyph: "󰻂", label: "Spacing",   section: "separators",
              description: "Widget gaps, compacting, and separators" },
            { glyph: "󰍴", label: "Underline", section: "underline",
              description: "Static line or reactive event glow" }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Arrange",    section: "widgets",
              description: "Order and visibility of bar widgets" },
            { glyph: "󰅐", label: "Clock",      section: "clock",
              description: "Date, time format, and seconds" },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces",
              description: "Workspace layout, labels, and window counts" },
            { glyph: "󰝚", label: "Media",      section: "media",
              description: "Track text and audio visualization" },
            { glyph: "󰈈", label: "Indicators", section: "indicators",
              description: "Titles, status widgets, and hover behavior" }
        ]},
        { glyph: "󰂚", label: "Feedback", children: [
            { glyph: "󰂚", label: "Notifications", section: "popups",
              description: "Placement, timing, and quiet hours" },
            { glyph: "󱀅", label: "OSD",    section: "osd",
              description: "Volume and brightness feedback" },
            { glyph: "󰀦", label: "Alerts", section: "warnings",
              description: "Battery and temperature warning thresholds" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰍉", label: "Interface", section: "interface",
              description: "Font, scale, contrast, motion, and display routing" },
            { glyph: "󰚰", label: "Updates", section: "updates",
              description: "Shell releases and system packages" }
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

    function toggleAt(x: real, screen): void {
        if (open) {
            close()
            return
        }
        anchorX = x
        triggerScreen = screen ?? null
        _activeTab = homeTab
        open = true
    }
    function close(): void {
        triggerScreen = null
        if (open) open = false
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
            root._activeTab = root.homeTab
            root.open = true
        }
        function close(): void { root.close() }
        function tab(index: int): string {
            if (index < root.homeTab || index > root.recentTab)
                return "unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (recent)"
            root.triggerScreen = null
            root.showTab(index)
            return "ok"
        }
        // keep `section: "` out of any literal below: ci-lint harvests nav entries by that pattern
        function settings(name: string): string {
            if (root._flatSections.indexOf(name) < 0)
                return "unknown settings page '" + name + "'; valid: " + root._flatSections.join(", ")
            root.triggerScreen = null
            root.setSettingsSection(name)
            root.showTab(root.settingsTab)
            return "ok"
        }
    }
}
