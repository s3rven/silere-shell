pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../config"

Singleton {
    id: root

    property var list: []
    property alias dnd:         _persist.dnd
    property alias missedCount: _persist.missedCount
    // these maps are restored from persisted JSON. Keep their prototype empty so a malformed key cannot change object behaviour between reloads
    property var _seen:  Object.create(null)
    property var _times: Object.create(null)
    property var _updateTimes: Object.create(null)
    property bool _persistentReady: false
    // settings.json loads asynchronously: trimming to the default before it lands drops
    // rows a larger configured limit keeps, and the trim is written straight back.
    // Arguments, not live state, so the rule is testable.
    function _capacityFor(limit: int, ceiling: int, settingsReady: bool): int {
        const configured = Math.max(5, limit)
        return settingsReady ? configured : Math.max(configured, ceiling)
    }
    readonly property int _historyCapacity: {
        const schema = ShellSettings.schemaFor("notifHistoryLimit")
        return root._capacityFor(ShellSettings.notifHistoryLimit,
            schema ? schema.max : 0, ShellSettings.ready)
    }
    readonly property int _maxIdentityChars: 512
    readonly property int _maxSummaryChars: 2048
    readonly property int _maxBodyChars: 16384
    readonly property int _maxSourceChars: IconResolver.maxSourceChars
    readonly property int activeCount: Array.isArray(list) ? list.length : 0

    // reassigning a var array resets the view — every delegate rebuilt, scroll to top, expanded card collapsed
    ListModel { id: _history }
    readonly property alias historyModel: _history
    readonly property int historyCount: _history.count
    readonly property bool hasHistory: _history.count > 0
    // at capacity a new notification inserts and trims in one go, so count alone holds
    // still while the contents move. Anything deriving rows from history must watch this
    property int historyRevision: 0

    // history is newest-first, so first-seen order is recency order: the app that spoke
    // last leads the rail. Rebuilt on revision, not count, for the reason above
    readonly property var historyApps: {
        root.historyRevision
        const order = []
        const byName = Object.create(null)
        for (let i = 0; i < _history.count; i++) {
            const e = _history.get(i)
            if (!e) continue
            const name = root.identityText(e.appName).trim()
            const key = name.length > 0 ? name : "Unknown"
            let row = byName[key]
            if (!row) {
                row = { appName: key, count: 0,
                        appIcon: e.appIcon ?? "", desktopEntry: e.desktopEntry ?? "" }
                byName[key] = row
                order.push(row)
            }
            row.count++
        }
        return order
    }


    function identityText(value): string {
        return SafeText.singleLineText(value, root._maxIdentityChars)
    }

    // roles are fixed by the first insert, so every entry (incl. one revived from JSON) needs the full shape
    function _normalizeEntry(e): var {
        if (!e || typeof e !== "object") return null
        const rawId = Number(e.id ?? -1)
        const rawUrgency = Number(e.urgency ?? 1)
        const rawTime = Number(e.time ?? 0)
        return {
            id:           isFinite(rawId) && rawId >= -1 && rawId <= 2147483647
                ? Math.trunc(rawId) : -1,
            appName:      root.identityText(e.appName),
            appIcon:      SafeText.boundedText(e.appIcon, root._maxSourceChars),
            desktopEntry: root.identityText(e.desktopEntry),
            summary:      root.plainText(e.summary, root._maxSummaryChars),
            body:         root.plainText(e.body, root._maxBodyChars),
            urgency:      isFinite(rawUrgency)
                ? Math.max(0, Math.min(2, Math.round(rawUrgency))) : 1,
            time:         isFinite(rawTime) && rawTime >= 0 && rawTime <= 8.64e15
                ? rawTime : 0,
            // coalesces replaces_id within one server lifetime; never persisted
            sessionCurrent: e.sessionCurrent === true
        }
    }

    function _trimHistory(): void {
        const dropped = []
        let removed = 0
        while (_history.count > root._historyCapacity) {
            const id = _history.get(_history.count - 1).id
            if (id !== undefined) dropped.push(String(id))
            _history.remove(_history.count - 1)
            removed++
        }
        if (removed > 0) root.historyRevision++
        root._forgetTrimmed(dropped)
    }

    // Clearing or restoring history leaves these maps whole. Drop entries that
    // belong to neither history nor a notification still owned by the server.
    function _pruneOrphanState(activeNotifications): void {
        const keep = Object.create(null)
        for (let i = 0; i < _history.count; i++) keep[String(_history.get(i).id)] = true
        // On a hot reload NotificationServer already owns its kept objects, but
        // root.list is rebuilt only after persisted timestamps are restored.
        // Include those objects now or their original age/read state is lost.
        const active = Array.isArray(activeNotifications) ? activeNotifications : []
        for (let i = 0; i < active.length; i++) {
            const entry = active[i]
            if (entry && entry.id !== undefined) keep[String(entry.id)] = true
        }
        const seen = Object.keys(root._seen)
            .concat(Object.keys(root._times), Object.keys(root._updateTimes))
        const stale = []
        for (let i = 0; i < seen.length; i++)
            if (keep[seen[i]] !== true && stale.indexOf(seen[i]) < 0) stale.push(seen[i])
        root._forgetTrimmed(stale)
    }

    // history is capped but these maps were not: an id that rolled off kept its seen
    // flag and timestamps for the life of the process, and every arrival re-serialized them
    function _forgetTrimmed(keys): void {
        if (keys.length === 0) return
        const live = Object.create(null)
        for (let i = 0; i < root.list.length; i++) live[String(root.list[i].id)] = true

        const seen = root._cloneMap(root._seen)
        const times = root._cloneMap(root._times)
        const updates = root._cloneMap(root._updateTimes)
        let cutSeen = false, cutTimes = false, cutUpdates = false

        for (let i = 0; i < keys.length; i++) {
            const key = keys[i]
            if (live[key] === true) continue
            if (key in seen)    { delete seen[key];    cutSeen = true }
            if (key in times)   { delete times[key];   cutTimes = true }
            if (key in updates) { delete updates[key]; cutUpdates = true }
        }

        if (cutSeen)    root._seen = seen
        if (cutTimes)   root._times = times
        if (cutUpdates) root._updateTimes = updates
    }

    function _prependHistory(entry): void {
        const e = root._normalizeEntry(entry)
        if (!e) return
        _history.insert(0, e)
        root.historyRevision++
        root._trimHistory()
    }

    function _saveHistory(): void {
        if (!root._persistentReady) return
        const out = []
        for (let i = 0; i < _history.count; i++) {
            const h = _history.get(i)
            out.push({
                id: h.id, appName: h.appName, appIcon: h.appIcon, desktopEntry: h.desktopEntry,
                summary: h.summary, body: h.body, urgency: h.urgency, time: h.time
            })
        }
        _persist.historyJson = ShellSettings.notifHistoryPersistent
            ? JSON.stringify(out) : "[]"
        root._queueDiskSave()
    }

    readonly property var popupModel: notifServer.trackedNotifications

    function _ensurePersistentState(): void {
        // var properties can be undefined for one frame during hot-reload
        if (!root._seen || typeof root._seen !== "object") root._seen = Object.create(null)
        if (!root._times || typeof root._times !== "object") root._times = Object.create(null)
        if (!root._updateTimes || typeof root._updateTimes !== "object")
            root._updateTimes = Object.create(null)
    }

    // a reload can run a save after this singleton's state is restored but before the
    // store below it exists; typeof keeps that window from throwing
    function _queueDiskSave(): void {
        if (typeof _diskStore !== "undefined") _diskStore.queue()
    }

    // a queued save must land before a reload replaces the engine; SIGTERM skips destruction
    Component.onDestruction: {
        if (typeof _diskStore !== "undefined" && _diskStore.pending) _diskStore.flush(true)
    }

    function _parsePersistentJson(raw: string, fallback): var {
        try { return JSON.parse(raw || "") }
        catch (e) { return fallback }
    }

    function _validStateId(value): bool {
        const text = String(value)
        if (!/^(0|[1-9][0-9]{0,9})$/.test(text)) return false
        const id = Number(text)
        return isFinite(id) && id <= 2147483647
    }

    function _normalizeSeenMap(map): var {
        const out = Object.create(null)
        if (!map || typeof map !== "object" || Array.isArray(map)) return out
        const keys = Object.keys(map)
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i]
            if (root._validStateId(key) && map[key] === true) out[key] = true
        }
        return out
    }

    function _normalizeTimesMap(map): var {
        const out = Object.create(null)
        if (!map || typeof map !== "object" || Array.isArray(map)) return out
        const keys = Object.keys(map)
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i]
            const value = Number(map[key])
            if (root._validStateId(key) && isFinite(value)
                    && value > 0 && value <= 8.64e15) out[key] = value
        }
        return out
    }

    function _restorePersistentState(activeNotifications): void {
        const savedHistory = ShellSettings.notifHistoryPersistent
            ? root._parsePersistentJson(_persist.historyJson, []) : []
        const savedSeen = root._parsePersistentJson(_persist.seenJson, Object.create(null))
        const savedTimes = root._parsePersistentJson(_persist.timesJson, Object.create(null))
        _history.clear()
        if (Array.isArray(savedHistory)) {
            for (let i = 0; i < savedHistory.length && i < root._historyCapacity; i++) {
                const e = root._normalizeEntry(savedHistory[i])
                if (e) {
                    // ids restart with the server, so a saved one names nothing this session
                    e.sessionCurrent = false
                    _history.append(e)
                }
            }
        }
        root.historyRevision++
        root._seen = root._normalizeSeenMap(savedSeen)
        root._times = root._normalizeTimesMap(savedTimes)
        root._ensurePersistentState()
        root._persistentReady = true
        root._pruneOrphanState(activeNotifications)
        root._saveHistory()
    }

    Connections {
        target: ShellSettings
        function onNotifPopupEnabledChanged() {
            if (!ShellSettings.notifPopupEnabled)
                root._retireActiveNotifications()
        }
        function onNotifHistoryLimitChanged() {
            root._trimHistory()
            root._saveHistory()
        }
        function onNotifHistoryPersistentChanged() {
            // privacy-first: turning persistence off removes text restored from an earlier session. New entries still form an in-memory history
            if (!ShellSettings.notifHistoryPersistent) {
                _history.clear()
                root.historyRevision++
                root._pruneOrphanState()
            }
            root._saveHistory()
        }
    }

    on_HistoryCapacityChanged: if (_persistentReady) { root._trimHistory(); root._saveHistory() }
    on_SeenChanged:   if (_persistentReady) _persist.seenJson = JSON.stringify(_seen)
    on_TimesChanged:  if (_persistentReady) _persist.timesJson = JSON.stringify(_times)

    function _cloneMap(map): var {
        const out = Object.create(null)
        if (!map || typeof map !== "object") return out
        const keys = Object.keys(map)
        for (let i = 0; i < keys.length; i++) out[keys[i]] = map[keys[i]]
        return out
    }

    function _ensureTime(id: int): real {
        root._ensurePersistentState()
        const key = String(id)
        const existing = root._times[key]
        if (existing !== undefined) return existing

        const now = Date.now()
        const next = root._cloneMap(root._times)
        next[key] = now
        root._times = next
        return now
    }

    function _forgetState(id: int): void {
        root._ensurePersistentState()
        const key = String(id)
        if (key in root._seen) {
            const nextSeen = root._cloneMap(root._seen)
            delete nextSeen[key]
            root._seen = nextSeen
        }
        if (key in root._times) {
            const nextTimes = root._cloneMap(root._times)
            delete nextTimes[key]
            root._times = nextTimes
        }
        if (key in root._updateTimes) {
            const nextUpdates = root._cloneMap(root._updateTimes)
            delete nextUpdates[key]
            root._updateTimes = nextUpdates
        }
    }

    function updateTimeFor(id: int): real {
        const v = root._updateTimes[String(id)]
        return v !== undefined ? v : root.timeFor(id)
    }

    // update timestamps are read only at explicit card lifecycle points, so changing
    // one does not need a fresh map (and a change signal) for every progress update
    function _recordUpdateTime(id: int, time: real): void {
        root._ensurePersistentState()
        root._updateTimes[String(id)] = time
    }

    // pure read; stamping here loops (createdAt binding reads _times then writes it), so the write lives in the arrival path
    function timeFor(id: int): real {
        const times = root._times
        if (times && typeof times === "object") {
            const v = times[String(id)]
            if (v !== undefined) return v
        }
        return Date.now()
    }

    // track object not just id — replaces_id reuses ids while old closed signal is pending
    property var _closing: ({})
    property bool lastCritical: false

    PersistentProperties {
        id: _persist
        reloadableId: "silereNotifications"
        property bool dnd: false
        property int  missedCount: 0
        // PersistentProperties survives an engine replacement; keep JS arrays serialized so values never cross engines
        property string historyJson: "[]"
        property string seenJson:  "{}"
        property string timesJson: "{}"
    }

    // PersistentProperties survives a config reload but not a restart, so the history
    // "Keep after restart" promises has to reach disk on its own
    PersistedFile {
        id: _diskStore
        path: ConfigStore.notificationsPath
        writeAllowed: false
        serialize: () => root._serializeDisk()
        onLoaded: raw => root._restoreFromDisk(raw)
        onLoadFailed: error => {
            _diskStore.writeAllowed = error === FileViewError.FileNotFound
        }
        onSaveFailed: error =>
            console.warn("silere-shell: failed to save notifications.json:", error)
    }

    // seen and times describe notifications the server still owns, and no server outlives a
    // restart; persisting them only lets a reissued id inherit a dead session's flags
    function _serializeDisk(): string {
        return JSON.stringify({
            __version: 1,
            history: root._parsePersistentJson(_persist.historyJson, [])
        })
    }

    function _restoreFromDisk(raw: string): void {
        const trimmed = String(raw || "").trim()
        try {
            const j = JSON.parse(trimmed || "{}")
            // a file written by a newer release is left exactly as it is; its entries may
            // carry fields this schema would drop on the next save
            const version = Number(j.__version ?? 0)
            const fromFuture = isFinite(version) && version > 1
            if (fromFuture)
                console.warn("silere-shell: notifications.json is from a newer version; keeping it as it is")
            // a reload already restored the same rows through _persist, so match on identity
            const present = Object.create(null)
            for (let i = 0; i < _history.count; i++) {
                const h = _history.get(i)
                present[String(h.id) + "\u0001" + String(h.time)] = true
            }
            if (ShellSettings.notifHistoryPersistent && Array.isArray(j.history)) {
                // the cap is the most this session can hold, so a pathological file cannot
                // freeze startup normalizing rows the trim would drop anyway
                const limit = _history.count + root._historyCapacity
                for (let i = 0; i < j.history.length && _history.count < limit; i++) {
                    const e = root._normalizeEntry(j.history[i])
                    if (!e) continue
                    const key = String(e.id) + "\u0001" + String(e.time)
                    if (present[key]) continue
                    present[key] = true
                    // ids restart with the server, so a saved one names nothing this session
                    e.sessionCurrent = false
                    _history.append(e)
                }
            }
            root._ensurePersistentState()
            root._trimHistory()
            root.historyRevision++
            _diskStore.lastSavedText = trimmed
            if (!fromFuture) {
                _diskStore.writeAllowed = true
                root._pruneOrphanState()
                root._saveHistory()
            }
        } catch (e) {
            // a file we could not read may still hold history; writing this session over it loses it
            _diskStore.writeAllowed = false
            console.warn("silere-shell: bad notifications.json, ignoring:", String(e))
        }
    }

    signal sourcePulse(int wsId, bool critical)
    signal contentUpdated(int notifId)
    signal notificationShown(string appName, string summary, bool critical)

    readonly property bool fullscreenSilenced: ShellSettings.notifFullscreenSilence
        && FullscreenState.active
    function toggleDnd(): void { dnd = !dnd }

    readonly property bool _quietActive: {
        if (!ShellSettings.dndSchedule) return false
        const from = ShellSettings.dndFrom, to = ShellSettings.dndTo
        if (from === to) return false
        const h = DateTime.hour24
        return from < to ? (h >= from && h < to) : (h >= from || h < to)
    }
    readonly property bool effectiveDnd: dnd || _quietActive
    readonly property bool silencingActive: effectiveDnd || fullscreenSilenced
    onSilencingActiveChanged: { if (!silencingActive && missedCount !== 0) missedCount = 0 }
    function markSeen(id: int): void {
        root._ensurePersistentState()
        const key = String(id)
        if (root._seen[key] === true) return
        const next = root._cloneMap(root._seen)
        next[key] = true
        root._seen = next
    }
    function isSeen(id: int):   bool { root._ensurePersistentState(); return !!_seen[id] }

    // the history page can be filtered to one app, where a Clear that took the rest with
    // it would be a trap. Empty name means the whole list
    function clearHistoryFor(appName: string): void {
        const want = root.identityText(appName).trim()
        if (want.length === 0) { root.clearHistory(); return }
        root._ensurePersistentState()
        const ids = []
        let removed = 0
        for (let i = _history.count - 1; i >= 0; i--) {
            const e = _history.get(i)
            const name = root.identityText(e.appName).trim()
            if ((name.length > 0 ? name : "Unknown") !== want) continue
            if (e.id !== undefined) ids.push(String(e.id))
            _history.remove(i)
            removed++
        }
        if (removed === 0) return
        root.historyRevision++
        root._forgetTrimmed(ids)
        root._saveHistory()
    }

    function clearHistory(): void {
        root._ensurePersistentState()
        if (_history.count === 0) return
        const ids = []
        for (let i = 0; i < _history.count; i++) {
            const id = _history.get(i).id
            if (id !== undefined) ids.push(String(id))
        }
        _history.clear()
        root.historyRevision++
        // one map copy per state kind, not one set of copies per history row
        root._forgetTrimmed(ids)
        root._saveHistory()
    }

    function _notificationHistoryEntry(notification, id: int, time: real): var {
        if (!notification || notification.transient) return null
        return {
            id:      id,
            appName: root.identityText(notification.appName),
            appIcon: SafeText.boundedText(notification.appIcon, root._maxSourceChars),
            desktopEntry: root.identityText(notification.desktopEntry),
            summary: root.plainText(notification.summary, root._maxSummaryChars),
            body:    root.plainText(notification.body),
            urgency: notification.urgency,
            time:    time,
            sessionCurrent: true
        }
    }

    function _historyEntry(e): var {
        if (!e || !e.notification) return null
        return root._notificationHistoryEntry(e.notification, e.id, root._times[e.id] ?? e.time)
    }

    function _archiveNotification(notification, id: int, time: real,
            saveHistory): bool {
        const entry = root._notificationHistoryEntry(notification, id, time)
        if (!entry) return false
        let replaced = false
        for (let i = _history.count - 1; i >= 0; i--) {
            const previous = _history.get(i)
            if (previous.id === id && previous.sessionCurrent === true) {
                _history.remove(i)
                root.historyRevision++
                replaced = true
            }
        }
        root._prependHistory(entry)
        if (saveHistory !== false) root._saveHistory()
        return !replaced
    }

    // Unloading the popup window destroys every card timer, but it does not
    // untrack the notifications held by the server. If popups are enabled
    // again those timerless cards otherwise return as stale notifications.
    function _retireActiveNotifications(): void {
        const active = Array.isArray(root.list) ? root.list.slice() : []
        if (active.length === 0) return

        // clear first: changing tracked may synchronously emit closed, and the close handler must not archive the same object a second time
        root.list = []
        root.lastCritical = false
        const retiredIds = []
        for (let i = 0; i < active.length; i++) {
            const e = active[i]
            if (!e) continue
            if (e.notification) {
                root._archiveNotification(e.notification, e.id,
                    root._times[e.id] ?? e.time ?? Date.now(), false)
                e.notification.tracked = false
            }
            retiredIds.push(String(e.id))
        }
        root._forgetTrimmed(retiredIds)
        // _archiveNotification normally persists immediately; this synchronous
        // batch reaches the same final history with one serialization
        root._saveHistory()
    }

    function _markClosing(id: int, notification): void {
        if (!notification) return
        const key = String(id)
        const list = root._closing[key] ? [...root._closing[key]] : []
        if (list.indexOf(notification) < 0) list.push(notification)
        root._closing[key] = list
    }

    function _consumeClosing(id: int, notification): bool {
        const key = String(id)
        const list = root._closing[key]
        if (!list) return false
        const idx = list.indexOf(notification)
        if (idx < 0) return false
        list.splice(idx, 1)
        if (list.length === 0) delete root._closing[key]
        else root._closing[key] = list
        return true
    }

    function _forget(id: int): void {
        root._forgetState(id)
        root._dropFromList([id])
    }

    function _dropFromList(ids): void {
        const drop = Object.create(null)
        for (let i = 0; i < ids.length; i++) drop[String(ids[i])] = true
        const next = []
        let changed = false
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (drop[String(e.id)] === true) changed = true
            else next.push(e)
        }
        if (changed) list = next
        if (list.length === 0 && lastCritical) lastCritical = false
    }

    function plainText(s, maxChars): string {
        if (!s) return ""
        const requested = Number(maxChars)
        const limit = isFinite(requested) && requested > 0
            ? Math.min(root._maxBodyChars, Math.floor(requested)) : root._maxBodyChars
        const source = SafeText.boundedText(s, limit * 2)
        const plain = source
            .replace(/<\/?(b|i|u|a|span|small|big|tt|markup|sub|sup|s)\b[^>]*>/gi, "")
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ").replace(/&hellip;/g, "…")
            .replace(/&amp;/g, "&")
            .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]/g, "")
        return SafeText.boundedText(plain, limit)
    }

    function notificationImageSource(raw): string {
        return IconResolver.senderImageSource(raw)
    }

    function resolveIconSource(raw): string {
        return IconResolver.iconSource(raw)
    }

    // DesktopEntries scans on first access and answers null until it lands, so the first
    // notification of a session resolves an empty icon and a plain lookup never re-runs
    property int entriesTick: 0
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.entriesTick++ }
    }

    // a sender often points at a temp file it deletes as soon as the call returns, and history
    // keeps that path for good; the desktop entry's icon outlives both
    function entryIconSource(desktopEntry, appName): string {
        const identity = root.identityText(desktopEntry || appName)
        const entry = DesktopEntries.heuristicLookup(identity)
        return entry && entry.icon ? root.resolveIconSource(entry.icon) : ""
    }

    function appIconSource(appIcon, desktopEntry, appName): string {
        const direct = IconResolver.senderIconSource(appIcon)
        if (direct.length > 0) return direct
        return root.entryIconSource(desktopEntry, appName)
    }

    function removeFromHistory(entry): void {
        let idx = -1
        if (typeof entry === "number") {
            idx = entry
        } else if (entry) {
            for (let i = 0; i < _history.count; i++) {
                const h = _history.get(i)
                if (h.id === entry.id && h.time === entry.time
                        && h.appName === entry.appName && h.summary === entry.summary) {
                    idx = i
                    break
                }
            }
        }
        if (idx < 0 || idx >= _history.count) return
        const id = _history.get(idx).id
        _history.remove(idx)
        root.historyRevision++
        root._saveHistory()
        // a reused id must not let an old row erase a live card's read/time state
        if (id !== undefined) root._forgetTrimmed([String(id)])
    }

    // _onClosed bails on a notification already marked closing, so the retirement below
    // is the only one that runs and a batch can safely defer it to one pass
    function _dismissObject(notifId: int, notification, expired,
            immediate): bool {
        const n = list.find(e => e.id === notifId && e.notification === notification)
        if (!n) return false
        const entry = root._historyEntry(n)
        root._markClosing(notifId, n.notification)
        // expire = timed out, dismiss = user closed
        if (expired === true) n.notification.expire()
        else                  n.notification.dismiss()
        if (entry) root._prependHistory(entry)
        if (immediate !== false) {
            if (entry) root._saveHistory()
            root._forget(notifId)
        }
        return true
    }

    function dismissObject(notifId: int, notification, expired): void {
        root._dismissObject(notifId, notification, expired, true)
    }

    function dismissObjects(items, expired): void {
        const pending = Array.isArray(items) ? items : []
        const retired = []
        for (let i = 0; i < pending.length; i++) {
            const item = pending[i]
            if (item && root._dismissObject(
                    item.id, item.notification, expired, false))
                retired.push(String(item.id))
        }
        if (retired.length === 0) return
        // drop first: _forgetTrimmed keeps the state of anything still listed
        root._dropFromList(retired)
        root._forgetTrimmed(retired)
        root._saveHistory()
    }

    // Closed by someone else: the sender withdrew it, or it answered our own
    // action.invoke() before the card's exit animation reached dismissObject.
    // Without archiving here the entry is dropped, so acting on a notification
    // loses it from history while dismissing one keeps it.
    function _onClosed(id: int, notification): void {
        if (root._consumeClosing(id, notification)) return
        const n = root.list.find(e => e.id === id && e.notification === notification)
        if (n) {
            const entry = root._historyEntry(n)
            if (entry) { root._prependHistory(entry); root._saveHistory() }
        }
        root._forget(id)
    }

    // quickshell mutates a tracked notification in place, so only a replaces_id object
    // needs a new list entry
    function _upsertActiveNotification(notification, arrivalTime: real): bool {
        const existing = root.list.findIndex(e => e.id === notification.id)
        if (existing < 0) {
            root.list = [...root.list, {
                notification: notification, id: notification.id, time: arrivalTime
            }]
            return true
        }

        const old = root.list[existing].notification
        if (old === notification) return false
        if (old) {
            root._markClosing(notification.id, old)
            old.tracked = false
        }
        const next = [...root.list]
        next[existing] = {
            notification: notification,
            id: notification.id,
            time: root.list[existing].time
        }
        root.list = next
        return true
    }

    Component.onCompleted: {
        ConfigStore.hardenQuickshellState()
        const vals = notifServer.trackedNotifications.values ?? []
        root._restorePersistentState(vals)
        root._ensurePersistentState()
        const rebuilt = []
        const live = {}
        const nextTimes = root._cloneMap(root._times)
        let timesChanged = false
        for (let i = 0; i < vals.length; i++) {
            const n = vals[i]
            if (!n) continue
            if (nextTimes[n.id] === undefined) {
                nextTimes[n.id] = Date.now()
                timesChanged = true
            }
            live[n.id] = true
            rebuilt.push({ notification: n, id: n.id, time: nextTimes[n.id] })
            n.closed.connect(() => root._onClosed(n.id, n))
        }
        if (rebuilt.length > 0) root.list = rebuilt
        const nextSeen = root._cloneMap(root._seen)
        let seenChanged = false
        for (const id in nextSeen) {
            if (!live[id]) {
                delete nextSeen[id]
                seenChanged = true
            }
        }
        for (const id in nextTimes) {
            if (!live[id]) {
                delete nextTimes[id]
                timesChanged = true
            }
        }
        if (seenChanged) root._seen = nextSeen
        if (timesChanged) root._times = nextTimes
        if (FullscreenState.wanted) Compositor.refreshToplevels()
    }

    NotificationServer {
        id: notifServer
        keepOnReload:        true
        bodySupported:       true
        bodyMarkupSupported: false
        actionsSupported:    true
        imageSupported:       true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: (n) => {
            root._ensurePersistentState()
            const bypasses = ShellSettings.notifCriticalBypass
                && n.urgency === NotificationUrgency.Critical
            if (root.effectiveDnd && !bypasses) {
                if (root._archiveNotification(n, n.id, Date.now()) || n.transient)
                    root.missedCount++
                n.tracked = false
                return
            }
            if (root.fullscreenSilenced && !bypasses) {
                if (root._archiveNotification(n, n.id, Date.now()) || n.transient)
                    root.missedCount++
                n.tracked = false
                return
            }
            if (!ShellSettings.notifPopupEnabled) {
                root._archiveNotification(n, n.id, Date.now())
                n.tracked = false
                return
            }
            const arrivalTime = root._ensureTime(n.id)
            root.lastCritical = n.urgency === NotificationUrgency.Critical

            root._recordUpdateTime(n.id, Date.now())
            const isNewObject = root._upsertActiveNotification(n, arrivalTime)
            // connect once per object — stacked handlers fire _onClosed twice
            if (isNewObject) n.closed.connect(() => root._onClosed(n.id, n))
            n.tracked = true
            if (!isNewObject) root.contentUpdated(n.id)
            else root.notificationShown(String(n.appName || ""), String(n.summary || ""),
                n.urgency === NotificationUrgency.Critical)

            if (ShellSettings.wsNotifPulse) {
                const srcWs = WindowActions.notificationSourceWorkspace(n)
                if (srcWs > 0) root.sourcePulse(srcWs, n.urgency === NotificationUrgency.Critical)
            }
        }
    }
}
