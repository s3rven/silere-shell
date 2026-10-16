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
    readonly property int mediaTab: 3
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
    readonly property bool mediaActive: open && activeTab === mediaTab

    // empty means every app; the rail owns the value, the page only reads it
    property string recentFilter: ""
    function setRecentFilter(name: string): void {
        root.recentFilter = String(name ?? "")
    }

    // hovering the active workspace is a strong signal that the menu is about
    // to open. Let the shell prepare its LazyLoader between frames, while
    // keeping ownership explicit so a rebuilt or second monitor cannot cancel
    // another bar's request
    property QtObject warmSource: null
    property var warmScreen: null
    readonly property bool warmRequested: warmSource !== null

    function requestWarm(source, screen): void {
        if (!source || root.open) return
        root.warmSource = source
        root.warmScreen = screen ?? null
        _warmExpiry.restart()
    }

    function cancelWarm(source): void {
        if (root.warmSource !== source) return
        _warmExpiry.stop()
        root.warmSource = null
        root.warmScreen = null
    }

    // a hover is only a speculative open: release the prepared window if no click follows
    Timer {
        id: _warmExpiry
        interval: 2500
        onTriggered: root.cancelWarm(root.warmSource)
    }

    property string settingsSection: "theme"

    // SelectRow dropdowns are inline, so two open at once stack their option
    // lists and retarget the panel height twice. Keep one owner for the whole
    // settings surface and ask the previous row to fold before the next opens
    property var _settingsSelectOwner: null
    readonly property bool settingsSelectOpen: _settingsSelectOwner !== null
    signal settingsSelectClaimed()
    function claimSettingsSelect(owner): void {
        if (!owner || _settingsSelectOwner === owner) return
        const previous = _settingsSelectOwner
        if (previous) previous._setOpen(false)
        _settingsSelectOwner = owner
        root.settingsSelectClaimed()
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
              description: "Colors, opacity, blur, and shadows" },
            { glyph: "󰛖", label: "Interface", section: "interface",
              description: "Text, accessibility, displays, and programs" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface",
              description: "Position, size, shape, and hover" },
            { glyph: "󰍴", label: "Underline", section: "underline",
              description: "Line and event glow" },
            { glyph: "󰤼", label: "Spacing",   section: "separators",
              description: "Gaps and dividers" }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Show & order", section: "widgets",
              description: "Choose and reorder bar widgets" },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces",
              description: "Markers, labels, and app icons" },
            { glyph: "󰅐", label: "Clock",      section: "clock",
              description: "Date, time, and calendar" },
            { glyph: "󰝚", label: "Media",      section: "media",
              description: "Track details and visualizer" },
            { glyph: "󰈈", label: "Indicators", section: "indicators",
              description: "Window title and status" }
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
            { glyph: "󰒓", label: "Overview", section: "updates",
              description: "Updates, diagnostics, and recovery" }
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

    readonly property var _settingsSearchAliases: ({
        theme: "accent wallpaper palette colors transparency frosted matugen dark black base border outline",
        interface: "font typeface text icons scale accessibility animations display monitor brightness lock command hyprlock swaylock gtklock night light hyprsunset wlsunset",
        surface: "bar position top bottom size shape corners rounded floating",
        underline: "underline glow screenshot pulse activity",
        separators: "spacing gaps dividers compact",
        widgets: "widgets show hide arrange reorder left center right tray",
        workspaces: "workspaces desktops markers numbers apps icons",
        clock: "clock time date calendar week sunday monday seconds twelve hour twenty four hour 12h 24h am pm",
        media: "music playback player tracks artwork spectrum visualizer cava audio",
        indicators: "window title battery wifi wi-fi network vpn bluetooth microphone status",
        popups: "notifications popup history retention quiet hours do not disturb dnd critical",
        osd: "on screen display volume sound audio brightness feedback integrated floating",
        warnings: "battery cpu temperature hot critical alerts threshold",
        updates: "updates version release install diagnostics health repair tools dependencies recovery reset defaults maintenance"
    })

    function _searchWords(text: string): string {
        return text.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/([a-z])([0-9])/g, "$1 $2").toLowerCase()
            .replace(/[^a-z0-9]+/g, " ").trim()
    }

    // build once from section metadata and setting names. Searching never creates section components or starts their hardware/tool probes
    readonly property var _settingsSearchEntries: {
        const keys = Object.create(null)
        const labels = Object.create(null)
        const keyWords = Object.create(null)
        const schema = ShellSettings._schema
        for (let i = 0; i < schema.length; i++) {
            const entry = schema[i]
            const label = entry.l || ""
            const words = " " + root._searchWords(entry.k + " " + label) + " "
            const sections = String(entry.sec).split(",")
            for (let j = 0; j < sections.length; j++) {
                const sec = sections[j]
                keys[sec] = (keys[sec] || "") + " " + entry.k
                labels[sec] = (labels[sec] || "") + " " + label
                if (!keyWords[sec]) keyWords[sec] = []
                keyWords[sec].push({ key: entry.k, label: label, words: words })
            }
        }
        const rows = []
        // a leading space lets a term match only where a word starts: "lock" must not find clock
        const spaced = text => " " + root._searchWords(text)
        for (let g = 0; g < root.settingsTree.length; g++) {
            const group = root.settingsTree[g]
            const children = group.children || [group]
            for (let i = 0; i < children.length; i++) {
                const child = children[i]
                rows.push({ section: child.section, label: child.label,
                    glyph: child.glyph, group: group.label,
                    order: rows.length,
                    keys: keyWords[child.section] || [],
                    labelWords: spaced(child.label),
                    groupWords: spaced(group.label),
                    featureWords: spaced((child.description || "") + " "
                        + (labels[child.section] || "") + " "
                        + (root._settingsSearchAliases[child.section] || "")),
                    words: spaced(group.label + " " + child.label + " "
                        + (child.description || "") + " " + (keys[child.section] || "")
                        + " " + (labels[child.section] || "")
                        + " " + (root._settingsSearchAliases[child.section] || "")) })
            }
        }
        return rows
    }

    function searchSettings(query: string): var {
        const words = root._searchWords(query.slice(0, 256))
        if (words.length === 0) return []
        const terms = words.split(" ").map(term => " " + term)
        const rank = row => terms.every(term => row.labelWords.indexOf(term) >= 0) ? 0
            : terms.every(term => row.groupWords.indexOf(term) >= 0) ? 1
            : terms.every(term => row.featureWords.indexOf(term) >= 0) ? 2 : 3
        return root._settingsSearchEntries.filter(row => terms.every(term => row.words.indexOf(term) >= 0))
            .sort((a, b) => rank(a) - rank(b) || a.order - b.order)
            .map(row => {
                const hit = root._matchedKey(row.keys, terms)
                return Object.assign({}, row, { key: hit ? hit.key : "", keyLabel: hit ? hit.label : "" })
            })
    }

    function _matchedKey(keys, terms): var {
        for (let i = 0; i < keys.length; i++)
            if (terms.every(term => keys[i].words.indexOf(term) >= 0)) return keys[i]
        return null
    }

    signal settingsSectionRequested()
    function setSettingsSection(s: string): void {
        // keep callers of the former diagnostics page on the combined overview
        const requested = s === "maintenance" ? "updates" : s
        const next = root._flatSections.indexOf(requested) >= 0 ? requested : "theme"
        root.settingsSectionRequested()
        if (next !== settingsSection) {
            root.closeSettingsSelect()
            settingsSection = next
        }
    }

    function _foldName(name): string {
        return String(name || "").toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    // folds only hand-typed ipc names; setSettingsSection stays exact so no caller lands on a page by accident
    function _ipcSection(name: string): string {
        const fold = root._foldName(name)
        if (fold.length === 0) return name
        if (fold === "maintenance" || fold === "diagnostics" || fold === "system") return "updates"
        for (let i = 0; i < root._flatSections.length; i++)
            if (root._foldName(root._flatSections[i]) === fold) return root._flatSections[i]
        for (let i = 0; i < settingsTree.length; i++) {
            const kids = settingsTree[i].children || []
            for (let j = 0; j < kids.length; j++)
                if (root._foldName(kids[j].label) === fold) return kids[j].section
        }
        return name
    }

    signal tabRequested(int index)
    // the window's height hold has to capture the old page before activeTab moves it
    signal tabChanging(int index)

    function _validTab(index: int): int {
        return Math.max(homeTab, Math.min(mediaTab, index))
    }

    // match the rail's visual order rather than the internal numeric ids
    function tabPosition(index: int): int {
        if (index === homeTab) return 0
        if (index === recentTab) return 1
        if (index === mediaTab) return 3
        return 2
    }

    function selectTab(index: int): int {
        const tab = root._validTab(index)
        if (tab !== settingsTab) root.closeSettingsSelect()
        if (root._activeTab !== tab) {
            root.tabChanging(tab)
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

    function showTabAt(tab: int, source, screen): void {
        const point = source ? source.mapToItem(null, source.width / 2, 0) : null
        root.selectTab(tab)
        root.openAt(point && isFinite(point.x) ? point.x : 10, screen, source)
        root.tabRequested(tab)
    }

    function showSettingsAt(section: string, source, screen): void {
        root.setSettingsSection(section)
        root.showTabAt(root.settingsTab, source, screen)
    }

    function toggleMediaAt(source, screen): void {
        if (root.open && root.activeTab === root.mediaTab) {
            root.close()
            return
        }
        root.showTabAt(root.mediaTab, source, screen)
    }

    readonly property string _refusedText: "error: the menu stays closed while the session is idle or the overview is open"

    IpcHandler {
        target: "menu"

        function toggle(): string {
            if (root.open) { root.close(); return "ok" }
            root.selectTab(root.homeTab)
            root.openUnanchored()
            return root.open ? "ok" : root._refusedText
        }
        function close(): void { root.close() }
        function tab(index: int): string {
            if (index < root.homeTab || index > root.mediaTab)
                return "error: unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (notifications), 3 (now playing)"
            if (index === root.mediaTab && !Media.shown)
                return "error: nothing is playing"
            root._unanchor()
            root.showTab(index)
            return root.open ? "ok" : root._refusedText
        }
        // keep `section: "` out of any literal below: ci-lint harvests nav entries by that pattern
        function settings(name: string): string {
            const resolved = root._ipcSection(name)
            const known = root._flatSections.indexOf(resolved) >= 0
            root._unanchor()
            root.setSettingsSection(resolved)
            root.showTab(root.settingsTab)
            if (!root.open) return root._refusedText
            if (known) return "ok"
            // pages get renamed; a keybind carrying an old name still opens Settings rather than doing nothing, and says why it landed somewhere else
            return "unknown settings page '" + name + "'; opened theme instead. valid: "
                + root._flatSections.join(", ")
        }
    }
}
