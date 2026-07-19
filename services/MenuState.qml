pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool open:    false
    property real anchorX: 10    // screen X of the trigger point; set before calling toggle()
    property var  triggerScreen: null  // ShellScreen the menu was opened from; null → focused
    property int  activeTab: 0

    // settings detail-pane selection; lives here so SettingsNav drives it and SettingsPage reads it (separate items)
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
        { glyph: "󰂚", label: "Notifications", children: [
            { glyph: "󰂚", label: "Popups", section: "popups",
              description: "Placement, timing, and quiet hours" },
            { glyph: "󱀅", label: "OSD",    section: "osd",
              description: "Volume and brightness feedback" },
            { glyph: "󰀦", label: "Alerts", section: "warnings",
              description: "Battery and temperature warning thresholds" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰢻", label: "General", section: "system",
              description: "Hardware, accessibility, and configuration" },
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
    readonly property int settingsSectionCount: _flatSections.length

    function setSettingsSection(s: string): void {
        if (s !== settingsSection) settingsSection = s
    }
    function stepSettingsSection(delta: int): void {
        const idx = _flatSections.indexOf(settingsSection)
        if (idx < 0) return
        const next = Math.max(0, Math.min(_flatSections.length - 1, idx + delta))
        if (next !== idx) settingsSection = _flatSections[next]
    }

    // lets pages request a tab switch (0 Home, 1 Settings, 2 Recent) without a panel reference
    signal tabRequested(int index)

    function toggleAt(x: real, screen): void {
        anchorX = x
        triggerScreen = screen ?? null
        open = !open
        if (!open) triggerScreen = null
    }
    function close():               void { triggerScreen = null; if (open) open = false }
    function showTab(index: int):   void { if (!open) open = true; tabRequested(index) }
}
