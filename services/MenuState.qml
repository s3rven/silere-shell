pragma Singleton

import QtQuick
import Quickshell.Io

AnchoredPopupState {
    id: root

    readonly property bool armed: true
    controlSurface: true
    anchorX: 10

    readonly property int homeTab: 0
    readonly property int settingsTab: 1
    readonly property int recentTab: 2
    property int _activeTab: homeTab
    property int _previousTab: homeTab
    readonly property int activeTab: _activeTab
    readonly property int previousTab: _previousTab
    readonly property int tabDirection: {
        const delta = tabPosition(activeTab) - tabPosition(previousTab)
        return delta === 0 ? 0 : (delta > 0 ? 1 : -1)
    }
    readonly property bool homeActive: open && activeTab === homeTab
    readonly property bool settingsActive: open && activeTab === settingsTab
    readonly property bool recentActive: open && activeTab === recentTab

    // empty means every app; the rail owns the value, the page only reads it
    property string recentFilter: ""
    function setRecentFilter(name: string): void {
        root.recentFilter = String(name ?? "")
    }

    // Hovering the active workspace is a strong signal that the menu is about
    // to open. Let the shell prepare its LazyLoader between frames, while
    // keeping ownership explicit so a rebuilt or second monitor cannot cancel
    // another bar's request.
    property QtObject warmSource: null
    property var warmScreen: null
    readonly property bool warmRequested: warmSource !== null

    function requestWarm(source, screen): void {
        if (!source || root.open) return
        root.warmSource = source
        root.warmScreen = screen ?? null
    }

    function cancelWarm(source): void {
        if (root.warmSource !== source) return
        root.warmSource = null
        root.warmScreen = null
    }

    property string settingsSection: "theme"

    // SelectRow dropdowns are inline, so two open at once stack their option
    // lists and retarget the panel height twice. Keep one owner for the whole
    // settings surface and ask the previous row to fold before the next opens.
    property var _settingsSelectOwner: null
    function claimSettingsSelect(owner): void {
        if (!owner || _settingsSelectOwner === owner) return
        const previous = _settingsSelectOwner
        if (previous) previous._setOpen(false)
        _settingsSelectOwner = owner
    }
    function releaseSettingsSelect(owner): void {
        if (_settingsSelectOwner === owner) _settingsSelectOwner = null
    }
    function closeSettingsSelect(): void {
        const previous = _settingsSelectOwner
        _settingsSelectOwner = null
        if (previous) previous._setOpen(false)
    }
    onOpenChanged: if (!open) closeSettingsSelect()

    // order by user impact and frequency: global appearance first, daily bar surfaces next, then feedback; operational and recovery tools stay last
    readonly property var settingsTree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme",
              description: "Colors, accent, and outlines" },
            { glyph: "󰍉", label: "Interface", section: "interface",
              description: "Font, scale, contrast, motion, and displays" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface",
              description: "Bar position, size, shape, and opacity" },
            { glyph: "󰍴", label: "Underline", section: "underline",
              description: "Line and event glow" },
            { glyph: "󰻂", label: "Spacing",   section: "separators",
              description: "Gaps and dividers" }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Show & order", section: "widgets",
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
        if (next !== settingsSection) {
            root.closeSettingsSelect()
            settingsSection = next
        }
    }

    // folds only hand-typed ipc names; setSettingsSection stays exact so no caller lands on a page by accident
    function _ipcSection(name: string): string {
        const fold = String(name || "").toLowerCase()
        for (let i = 0; i < root._flatSections.length; i++)
            if (root._flatSections[i].toLowerCase() === fold) return root._flatSections[i]
        return name
    }

    signal tabRequested(int index)

    function _validTab(index: int): int {
        return Math.max(homeTab, Math.min(recentTab, index))
    }

    // Match the rail's visual order rather than the internal numeric ids.
    function tabPosition(index: int): int {
        if (index === homeTab) return 0
        if (index === recentTab) return 1
        return 2
    }

    function selectTab(index: int): int {
        const tab = root._validTab(index)
        if (tab !== settingsTab) root.closeSettingsSelect()
        if (root._activeTab !== tab) {
            root._previousTab = root._activeTab
            root._activeTab = tab
        }
        return tab
    }

    function toggleAt(x: real, screen, source): void {
        if (open) {
            close()
            return
        }
        selectTab(homeTab)
        openAt(x, screen, source)
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
            root.selectTab(root.homeTab)
            root.openUnanchored()
        }
        function close(): void { root.close() }
        function tab(index: int): string {
            if (index < root.homeTab || index > root.recentTab)
                return "unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (recent)"
            root._unanchor()
            root.showTab(index)
            return "ok"
        }
        // keep `section: "` out of any literal below: ci-lint harvests nav entries by that pattern
        function settings(name: string): string {
            const resolved = root._ipcSection(name)
            const known = root._flatSections.indexOf(resolved) >= 0
            root._unanchor()
            root.setSettingsSection(resolved)
            root.showTab(root.settingsTab)
            if (known) return "ok"
            // pages get renamed; a keybind carrying an old name still opens Settings rather than doing nothing, and says why it landed somewhere else
            return "unknown settings page '" + name + "'; opened theme instead. valid: "
                + root._flatSections.join(", ")
        }
    }
}
