pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var list: []
    property alias dnd:         _persist.dnd
    property alias missedCount: _persist.missedCount
    // These maps are restored from persisted JSON. Keep their prototype empty
    // so a malformed key cannot change object behaviour between reloads.
    property var _seen:  Object.create(null)
    property var _times: Object.create(null)
    property var _updateTimes: Object.create(null)
    property bool _persistentReady: false
    readonly property int _maxHistory: Math.max(5, ShellSettings.notifHistoryLimit)
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
                ? rawTime : 0
        }
    }

    function _trimHistory(): void {
        const dropped = []
        while (_history.count > root._maxHistory) {
            const id = _history.get(_history.count - 1).id
            if (id !== undefined) dropped.push(String(id))
            _history.remove(_history.count - 1)
        }
        root._forgetTrimmed(dropped)
    }

    // clearing or restoring history leaves the maps whole; anything history no longer
    // covers is dead weight that only a restart could clear
    function _pruneOrphanState(): void {
        const keep = Object.create(null)
        for (let i = 0; i < _history.count; i++) keep[String(_history.get(i).id)] = true
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
    }

    readonly property var popupModel: notifServer.trackedNotifications

    function _ensurePersistentState(): void {
        // var properties can be undefined for one frame during hot-reload
        if (!root._seen || typeof root._seen !== "object") root._seen = Object.create(null)
        if (!root._times || typeof root._times !== "object") root._times = Object.create(null)
    }

    function _parsePersistentJson(raw: string, fallback): var {
        try { return JSON.parse(raw || "") }
        catch (e) { return fallback }
    }

    function _restorePersistentState(): void {
        const savedHistory = ShellSettings.notifHistoryPersistent
            ? root._parsePersistentJson(_persist.historyJson, []) : []
        const savedSeen = root._parsePersistentJson(_persist.seenJson, Object.create(null))
        const savedTimes = root._parsePersistentJson(_persist.timesJson, Object.create(null))
        _history.clear()
        if (Array.isArray(savedHistory)) {
            for (let i = 0; i < savedHistory.length && i < root._maxHistory; i++) {
                const e = root._normalizeEntry(savedHistory[i])
                if (e) _history.append(e)
            }
        }
        root._seen = root._cloneMap(savedSeen)
        root._times = root._cloneMap(savedTimes)
        root._persistentReady = true
        root._pruneOrphanState()
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
            // Privacy-first: turning persistence off removes text restored from
            // an earlier session. New entries still form an in-memory history.
            if (!ShellSettings.notifHistoryPersistent) {
                _history.clear()
                root._pruneOrphanState()
            }
            root._saveHistory()
        }
    }

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

    signal sourcePulse(int wsId, bool critical)
    signal contentUpdated(int notifId)
    signal notificationShown(string appName, string summary, bool critical)

    readonly property bool _fullscreenWatchWanted: ShellSettings.notifFullscreenSilence
        || ShellSettings.mediaProgress
        || (ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated)
    readonly property bool _fullscreenActive: _fullscreenWatchWanted && Compositor.activeFullscreen
    readonly property bool fullscreenActive: _fullscreenActive
    readonly property bool fullscreenSilenced: ShellSettings.notifFullscreenSilence && _fullscreenActive

    function refreshFullscreenState(): void { Compositor.refreshToplevels() }
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

    function clearHistory(): void {
        root._ensurePersistentState()
        if (_history.count === 0) return
        for (let i = 0; i < _history.count; i++) {
            const id = _history.get(i).id
            if (id !== undefined) root._forgetState(id)
        }
        _history.clear()
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
            time:    time
        }
    }

    function _historyEntry(e): var {
        if (!e || !e.notification) return null
        return root._notificationHistoryEntry(e.notification, e.id, root._times[e.id] ?? e.time)
    }

    function _archiveNotification(notification, id: int, time: real): bool {
        const entry = root._notificationHistoryEntry(notification, id, time)
        if (!entry) return false
        let replaced = false
        for (let i = _history.count - 1; i >= 0; i--) {
            if (_history.get(i).id === id) { _history.remove(i); replaced = true }
        }
        root._prependHistory(entry)
        root._saveHistory()
        return !replaced
    }

    // Unloading the popup window destroys every card timer, but it does not
    // untrack the notifications held by the server. If popups are enabled
    // again those timerless cards otherwise return as stale notifications.
    function _retireActiveNotifications(): void {
        const active = Array.isArray(root.list) ? root.list.slice() : []
        if (active.length === 0) return

        // Clear first: changing tracked may synchronously emit closed, and the
        // close handler must not archive the same object a second time.
        root.list = []
        root.lastCritical = false
        for (let i = 0; i < active.length; i++) {
            const e = active[i]
            if (!e) continue
            if (e.notification) {
                root._archiveNotification(e.notification, e.id,
                    root._times[e.id] ?? e.time ?? Date.now())
                e.notification.tracked = false
            }
            root._forgetState(e.id)
        }
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
        const next = []
        let changed = false
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (e.id === id) {
                changed = true
            } else {
                next.push(e)
            }
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

    // bare absolute paths resolve against the qml context (qrc:/...) and fail to load
    function fileUrl(raw): string {
        return IconResolver.localSource(raw)
    }

    function resolveIconSource(raw): string {
        return IconResolver.iconSource(raw)
    }

    function appIconSource(appIcon, desktopEntry, appName): string {
        const direct = root.resolveIconSource(appIcon)
        if (direct.length > 0) return direct
        const identity = root.identityText(desktopEntry || appName)
        const entry = DesktopEntries.heuristicLookup(identity)
        return entry && entry.icon ? root.resolveIconSource(entry.icon) : ""
    }

    function removeFromHistory(entry): void {
        let idx = -1
        if (typeof entry === "number") {
            idx = entry
        } else if (entry) {
            for (let i = 0; i < _history.count; i++) {
                const h = _history.get(i)
                if (h.time === entry.time && h.summary === entry.summary) { idx = i; break }
            }
        }
        if (idx < 0 || idx >= _history.count) return
        const id = _history.get(idx).id
        _history.remove(idx)
        root._saveHistory()
        if (id !== undefined) root._forgetState(id)
    }

    function dismissObject(notifId: int, notification, expired): void {
        const n = list.find(e => e.id === notifId && e.notification === notification)
        if (!n) return
        const entry = root._historyEntry(n)
        root._markClosing(notifId, n.notification)
        // expire = timed out, dismiss = user closed
        if (expired === true) n.notification.expire()
        else                  n.notification.dismiss()
        if (entry) { root._prependHistory(entry); root._saveHistory() }
        root._forget(notifId)
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

    Component.onCompleted: {
        ConfigStore.hardenQuickshellState()
        root._restorePersistentState()
        root._ensurePersistentState()
        const vals = notifServer.trackedNotifications.values ?? []
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
        if (root._fullscreenWatchWanted) Compositor.refreshToplevels()
    }

    NotificationServer {
        id: notifServer
        keepOnReload:        true
        bodySupported:       true
        bodyMarkupSupported: false
        actionsSupported:    true
        imageSupported:       true
        persistenceSupported: true

        onNotification: (n) => {
            root._ensurePersistentState()
            if (root.effectiveDnd && n.urgency !== NotificationUrgency.Critical) {
                if (root._archiveNotification(n, n.id, Date.now()) || n.transient)
                    root.missedCount++
                n.tracked = false
                return
            }
            if (root.fullscreenSilenced && n.urgency !== NotificationUrgency.Critical) {
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

            const updates = root._cloneMap(root._updateTimes)
            updates[String(n.id)] = Date.now()
            root._updateTimes = updates

            const existing = root.list.findIndex(e => e.id === n.id)
            let isNewObject = true
            if (existing >= 0) {
                const old = root.list[existing].notification
                isNewObject = old !== n
                if (old && isNewObject) {
                    root._markClosing(n.id, old)
                    old.tracked = false
                }
                const next = [...root.list]
                next[existing] = { notification: n, id: n.id, time: root.list[existing].time }
                root.list = next
            } else {
                root.list = [...root.list, { notification: n, id: n.id, time: arrivalTime }]
            }
            // connect once per object — stacked handlers fire _onClosed twice
            if (isNewObject) n.closed.connect(() => root._onClosed(n.id, n))
            n.tracked = true
            if (existing >= 0 && !isNewObject) root.contentUpdated(n.id)
            else root.notificationShown(String(n.appName || ""), String(n.summary || ""),
                n.urgency === NotificationUrgency.Critical)

            if (ShellSettings.wsNotifPulse) {
                const srcWs = HyprActions.notificationSourceWorkspace(n)
                if (srcWs > 0) root.sourcePulse(srcWs, n.urgency === NotificationUrgency.Critical)
            }
        }
    }
}
