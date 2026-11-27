pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsTree.js" as SettingsTree

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

    // the heights Settings, its nav and History closed at: the menu's window unloads a moment after it closes, so a
    // reopen builds them again and opens at these instead of growing from the placeholder's while the page fades in
    property real settingsClosedHeight: 0
    property string settingsClosedSection: ""
    property real settingsNavClosedHeight: 0
    property real recentClosedHeight: 0

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
    property var surfaceScreen: null
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
    property var settingsSelectOwner: null
    readonly property bool settingsSelectOpen: settingsSelectOwner !== null
    signal settingsSelectClaimed()
    // a switch flipped by hand: the rows it opens can land under the edge of a capped page
    signal settingsRevealRequested(Item row)
    function claimSettingsSelect(owner): void {
        if (!owner || settingsSelectOwner === owner) return
        const previous = settingsSelectOwner
        if (previous) previous._setOpen(false)
        settingsSelectOwner = owner
        root.settingsSelectClaimed()
    }
    function releaseSettingsSelect(owner): void {
        if (settingsSelectOwner === owner) settingsSelectOwner = null
    }
    function closeSettingsSelect(): void {
        const previous = settingsSelectOwner
        settingsSelectOwner = null
        if (previous) previous._setOpen(false)
    }
    onOpenChanged: {
        // on the way in, so a closing History keeps its rows; a missed-notification badge must not land on last time's app
        if (open) recentFilter = ""
        else {
            closeSettingsSelect()
            homePicker = ""
        }
    }

    readonly property var settingsTree: SettingsTree.tree
    readonly property var flatSections: SettingsTree.flatSections

    readonly property var _settingsSearchAliases: ({
        theme: "accent wallpaper palette colors transparency transparent frosted matugen dark light mode black base border outline",
        interface: "font typeface text size bigger larger smaller zoom icons scale accessibility animations contrast menu groups",
        keybinds: "shortcuts hotkeys bindings binds cheatsheet hyprland",
        devices: "display monitor screen multi primary brightness ddc ddcutil external backlight keyboard light bluetooth controller adapter lock command hyprlock swaylock gtklock night light blue hyprsunset wlsunset dock overlay",
        surface: "bar position top bottom size shape corners rounded floating margin tooltip",
        underline: "underline glow screenshot pulse activity",
        separators: "spacing gaps padding dividers compact",
        widgets: "widgets show hide arrange reorder left center right tray all apps layout caps lock",
        workspaces: "workspaces desktops markers numbers apps icons",
        clock: "clock time date calendar week sunday monday seconds twelve hour twenty four hour 12h 24h am pm temperature forecast",
        media: "music now playing playback player tracks artwork album cover art spectrum visualizer cava audio",
        indicators: "window title battery wifi wi-fi network vpn bluetooth microphone status ram",
        popups: "notifications popup quiet hours do not disturb dnd critical",
        history: "notification history retention saved muted mute apps clear limit",
        osd: "on screen display volume sound audio brightness feedback popup integrated floating",
        warnings: "battery cpu temperature hot overheating critical alerts threshold",
        updates: "updates version release changelog install diagnostics health repair tools dependencies recovery reset restore defaults maintenance daily shell check doctor fix problems"
    })

    // the words a row shows besides its title (its chips) or answers to, so the row itself is found and flashed.
    // A real word the index lacks is otherwise "corrected" to a near one: wave found History, charging found screen sharing
    readonly property var _settingsKeyAliases: ({
        mediaVisualizerStyle: "wave bars pulse",
        mediaVisualizerPreset: "eco balanced smooth",
        barHeight: "compact tall",
        barSpacing: "tight wide",
        wsActiveMarker: "gem dot line",
        dotStyle: "bullet ring slash",
        barSeparatorMode: "groups every",
        notifMaxVisible: "stack",
        calendarWeekStart: "first day",
        weatherEnabled: "location",
        nightLightProvider: "nightlight warm sunset sunrise redshift",
        // off shows the battery percentage and other readings all the time
        valuesOnHover: "battery percentage",
        batteryAutoHide: "charging plugged",
        osdChargedNotify: "charging",
        uiScale: "scaling",
        trayWidget: "systray",
        systemRings: "rings circles gauges",
        weatherUnit: "celsius fahrenheit"
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
        const schema = ShellSettings.schema
        // the bar's widget toggles show the widget's own name
        const widgetLabels = Object.create(null)
        for (const id in ShellSettings.barWidgetMeta) {
            const meta = ShellSettings.barWidgetMeta[id]
            if (meta.setting) widgetLabels[meta.setting] = meta.label
        }
        // a leading space lets a term match only where a word starts: "lock" must not find clock
        const spaced = text => " " + root._searchWords(text)
        for (let i = 0; i < schema.length; i++) {
            const entry = schema[i]
            const label = entry.l || widgetLabels[entry.k] || ""
            const alias = root._settingsKeyAliases[entry.k] || ""
            const words = " " + root._searchWords(entry.k + " " + label + " " + alias) + " "
            const sections = String(entry.sec).split(",")
            for (let j = 0; j < sections.length; j++) {
                const sec = sections[j]
                keys[sec] = (keys[sec] || "") + " " + entry.k + " " + alias
                labels[sec] = (labels[sec] || "") + " " + label
                if (!keyWords[sec]) keyWords[sec] = []
                keyWords[sec].push({ key: entry.k, label: label, words: words, labelWords: spaced(label) })
            }
        }
        const rows = []
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
                    descriptionWords: spaced(child.description || ""),
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
        const text = query.slice(0, 256)
        const identifier = text.trim().toLowerCase()
        // a pasted setting name identifies a row even when its words match another page
        if (/^[a-z][a-z0-9]*$/.test(identifier)) {
            const exact = []
            for (const row of root._settingsSearchEntries) {
                const match = row.keys.find(entry => entry.key.toLowerCase() === identifier)
                if (match) exact.push(Object.assign({}, row, {
                    key: match.key, keyLabel: match.label || match.key
                }))
            }
            if (exact.length > 0) return exact
        }
        const words = root._searchWords(text)
        if (words.length === 0) return []
        const found = root._searchTerms(words)
        if (found.length > 0) return found
        const fixed = words.split(" ").map(term => root._correctedTerm(term)).join(" ")
        return fixed === words ? [] : root._searchTerms(fixed)
    }

    // every word the index knows, for typo correction
    readonly property var _searchVocabulary: {
        const seen = Object.create(null)
        for (const row of root._settingsSearchEntries)
            for (const word of row.words.split(" "))
                if (word.length > 2) seen[word] = true
        return Object.keys(seen)
    }

    // a word nothing starts with becomes the closest start of an indexed word: one slip (a swap counts as one), two from 8 letters
    function _correctedTerm(term: string): string {
        const length = term.length
        if (length < 4 || root._searchVocabulary.some(w => w.startsWith(term))) return term
        const most = length >= 8 ? 2 : 1
        // longer terms can match a prefix at a nearby length, as in "colour" and "color" from "colors"
        const reach = length >= 5 ? most : 0
        let best = term, bestCost = most + 1
        for (const word of root._searchVocabulary) {
            // a slip in the first letter and the second at once is rare, and skipping those keeps a keystroke cheap
            if (word.length < length - most || (word[0] !== term[0] && word[1] !== term[1])) continue
            const first = Math.min(word.length, length - reach)
            const last = word.length <= length + most ? word.length : length + reach
            const hit = root._closestPrefix(term, word, first, last)
            if (hit.cost < bestCost || (hit.cost === bestCost && word[0] === term[0] && best[0] !== term[0])) {
                best = word.slice(0, hit.length)
                bestCost = hit.cost
            }
        }
        return best
    }

    // the last row of optimal string alignment holds the distance to every prefix, including transpositions
    function _closestPrefix(a: string, b: string, first: int, last: int): var {
        let prev2 = [], prev = Array.from({ length: last + 1 }, (_, j) => j)
        for (let i = 1; i <= a.length; i++) {
            const row = [i]
            for (let j = 1; j <= last; j++) {
                row[j] = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                    row[j] = Math.min(row[j], prev2[j - 2] + 1)
            }
            prev2 = prev
            prev = row
        }
        let length = last
        for (let j = last - 1; j >= first; j--) if (prev[j] < prev[length]) length = j
        return { cost: prev[length], length: length }
    }

    function _searchTerms(words: string): var {
        const terms = words.split(" ").map(term => " " + term)
        const phrase = " " + words
        const within = text => terms.every(term => text.indexOf(term) >= 0)
        // a page, its group, a row titled exactly this ("App icon" is not "App icons"), the page's own summary, any row title
        const rank = row => within(row.labelWords) ? 0
            : within(row.groupWords) ? 1
            : row.keys.some(k => k.labelWords === phrase) ? 2
            : within(row.descriptionWords) ? 3
            : row.keys.some(k => within(k.labelWords)) ? 4
            : within(row.featureWords) ? 5 : 6
        return root._settingsSearchEntries.filter(row => terms.every(term => row.words.indexOf(term) >= 0))
            .sort((a, b) => rank(a) - rank(b) || a.order - b.order)
            .map(row => {
                const hit = row.keys.find(k => k.labelWords === phrase) ?? root._matchedKey(row.keys, terms)
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
        const next = root.flatSections.indexOf(requested) >= 0 ? requested : "theme"
        root.settingsSectionRequested()
        if (next !== settingsSection) {
            root.closeSettingsSelect()
            settingsSection = next
        }
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

    // the next tab in the rail's order, around the ends; Now Playing is only there while something plays
    function adjacentTab(index: int, mediaShown: bool, step: int): int {
        const order = mediaShown ? [homeTab, recentTab, settingsTab, mediaTab] : [homeTab, recentTab, settingsTab]
        const at = Math.max(0, order.indexOf(index))
        return order[(at + step + order.length) % order.length]
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
    function showTabUnanchored(index: int): void {
        root._unanchor()
        root.showTab(index)
    }

    function showTabAt(tab: int, source, screen): void {
        const point = source ? source.mapToItem(null, source.width / 2, 0) : null
        root.selectTab(tab)
        root.openAt(point && isFinite(point.x) ? point.x : 10, screen, source)
        root.tabRequested(tab)
    }

    // the drawer a bar icon stands for (the network icon's Wi-Fi list), for Home to open as it shows;
    // one-shot, and dropped with the menu so a later plain open cannot inherit it
    property string homePicker: ""
    function showHomeAt(picker: string, source, screen): void {
        root.homePicker = picker
        root.showTabAt(root.homeTab, source, screen)
        if (!root.open) root.homePicker = ""
    }

    function showSettingsAt(section: string, source, screen): void {
        root.setSettingsSection(section)
        root.showTabAt(root.settingsTab, source, screen)
    }

    function toggleTabAt(tab: int, source, screen): void {
        if (root.open && root.activeTab === tab) {
            root.close()
            return
        }
        root.showTabAt(tab, source, screen)
    }

    // a page compiled after its files changed can fail against types compiled at start; only a new engine clears them
    PersistentProperties {
        id: _reloadReturn
        reloadableId: "silereMenuReload"
        property int tab: -1
        property string section: ""
        onReloaded: if (_reloadReturn.tab >= 0) Qt.callLater(root._returnAfterReload)
    }
    property bool reloadPending: false
    function reloadShell(): void {
        if (root.reloadPending) return
        _reloadReturn.tab = root.open ? root.activeTab : -1
        _reloadReturn.section = root.settingsSection
        root.reloadPending = true
        root.close()
        _reloadFallback.restart()
    }
    // an open menu torn down by a reload logs a warning per live binding; the shell calls this once it has unloaded
    function reloadNow(): void {
        if (!root.reloadPending) return
        root.reloadPending = false
        _reloadFallback.stop()
        Qt.callLater(() => Quickshell.reload(false))
    }
    Timer {
        id: _reloadFallback
        interval: 1500
        onTriggered: root.reloadNow()
    }
    function _returnAfterReload(): void {
        const tab = _reloadReturn.tab
        _reloadReturn.tab = -1
        if (tab < 0) return
        root.setSettingsSection(_reloadReturn.section)
        root._unanchor()
        root.showTab(tab)
    }
    Connections {
        target: Quickshell
        function onReloadFailed() {
            _reloadReturn.tab = -1
            root.reloadPending = false
        }
    }

    readonly property string _refusedText: "error: the menu stays closed while the session is idle or the overview is open"

    // the IPC call and the Hyprland global shortcut open Home the same way
    function keybindToggle(): string {
        if (root.open) { root.close(); return "ok" }
        root.selectTab(root.homeTab)
        root.openUnanchored()
        return root.open ? "ok" : root._refusedText
    }

    IpcHandler {
        target: "menu"

        function toggle(): string { return root.keybindToggle() }
        function close(): void { root.close() }
        function tab(index: int): string {
            if (index < root.homeTab || index > root.mediaTab)
                return "error: unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (notifications), 3 (now playing)"
            if (index === root.mediaTab && !Media.menuShown)
                return "error: nothing is playing"
            root.showTabUnanchored(index)
            return root.open ? "ok" : root._refusedText
        }
        function settings(name: string): string {
            const resolved = SettingsTree.ipcSection(name)
            const known = root.flatSections.indexOf(resolved) >= 0
            root._unanchor()
            root.setSettingsSection(resolved)
            root.showTab(root.settingsTab)
            if (!root.open) return root._refusedText
            if (known) return "ok"
            // pages get renamed; a keybind carrying an old name still opens Settings rather than doing nothing, and says why it landed somewhere else
            return "unknown settings page '" + name + "'; opened theme instead. valid: "
                + root.flatSections.join(", ")
        }
    }
}
