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
            { glyph: "󰉦", label: "Theme",       section: "theme"      },
            { glyph: "󰖙", label: "Night light", section: "nightlight" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface"    },
            { glyph: "󰻂", label: "Spacing",   section: "separators" },
            { glyph: "󰍴", label: "Underline", section: "underline"  }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Arrange",    section: "widgets"    },
            { glyph: "󰅐", label: "Clock",      section: "clock"      },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces" },
            { glyph: "󰝚", label: "Media",      section: "media"      },
            { glyph: "󰈈", label: "Indicators", section: "indicators" }
        ]},
        { glyph: "󰂚", label: "Notifications", children: [
            { glyph: "󰂚", label: "Popups", section: "popups"   },
            { glyph: "󱀅", label: "OSD",    section: "osd"      },
            { glyph: "󰀦", label: "Alerts", section: "warnings" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰢻", label: "General", section: "system"  },
            { glyph: "󰚰", label: "Updates", section: "updates" }
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
