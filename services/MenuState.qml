pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool open:    false
    property real anchorX: 10    // screen X of the trigger point; set before calling toggle()
    property var  triggerScreen: null  // ShellScreen the menu was opened from; null → focused
    property int  activeTab: 0

    // Settings detail-pane selection. Lives here (not in the page) so the rail's
    // SettingsNav drives it and SettingsPage reads it — they're separate items now.
    property string settingsSection: "theme"

    readonly property var settingsTree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme"      },
            { glyph: "󱖲", label: "Motion",      section: "motion"     },
            { glyph: "󰖙", label: "Night Light", section: "nightlight" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Surface",    section: "surface"    },
            { glyph: "󰻂", label: "Separators", section: "separators" },
            { glyph: "󰍴", label: "Underline",  section: "underline"  }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰅐", label: "Clock",      section: "clock"      },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces" },
            { glyph: "󰝚", label: "Media",      section: "media"      },
            { glyph: "󰈈", label: "Indicators", section: "indicators" }
        ]},
        { glyph: "󰂚", label: "Notifications", children: [
            { glyph: "󰂚", label: "Popups",   section: "popups"   },
            { glyph: "󱀅", label: "OSD",      section: "osd"      },
            { glyph: "󰀦", label: "Warnings", section: "warnings" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰒓", label: "General", section: "system"  },
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

    // Lets pages ask the menu to switch tabs (0 Home, 1 Settings, 2 Recent)
    // without holding a reference to the panel.
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
