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
    property var _seen:  ({})
    property var _times: ({})
    // last content-update stamp; drives the popup dwell, not persisted
    property var _updateTimes: ({})
    property bool _persistentReady: false
    readonly property int _maxHistory: 20
    readonly property int activeCount: Array.isArray(list) ? list.length : 0

    // reassigning a var array resets the view — every delegate rebuilt, scroll to top, expanded card collapsed
    ListModel { id: _history }
    readonly property alias historyModel: _history
    readonly property int historyCount: _history.count
    readonly property bool hasHistory: _history.count > 0

    // roles are fixed by the first insert, so every entry (incl. one revived from JSON) needs the full shape
    function _normalizeEntry(e): var {
        if (!e || typeof e !== "object") return null
        return {
            id:           Number(e.id ?? -1),
            appName:      String(e.appName ?? ""),
            appIcon:      String(e.appIcon ?? ""),
            desktopEntry: String(e.desktopEntry ?? ""),
            summary:      String(e.summary ?? ""),
            body:         String(e.body ?? ""),
            urgency:      Number(e.urgency ?? 1),
            time:         Number(e.time ?? 0)
        }
    }

    function _trimHistory(): void {
        while (_history.count > root._maxHistory) _history.remove(_history.count - 1)
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
        _persist.historyJson = JSON.stringify(out)
    }

    // popups use the live ObjectModel so new cards don't cause a full Repeater rebuild
    readonly property var popupModel: notifServer.trackedNotifications

    function _ensurePersistentState(): void {
        // var properties can be undefined for one frame during hot-reload
        if (!root._seen || typeof root._seen !== "object") root._seen = ({})
        if (!root._times || typeof root._times !== "object") root._times = ({})
    }

    function _parsePersistentJson(raw: string, fallback): var {
        try { return JSON.parse(raw || "") }
        catch (e) { return fallback }
    }

    function _restorePersistentState(): void {
        const savedHistory = root._parsePersistentJson(_persist.historyJson, [])
        const savedSeen = root._parsePersistentJson(_persist.seenJson, ({}))
        const savedTimes = root._parsePersistentJson(_persist.timesJson, ({}))
        _history.clear()
        if (Array.isArray(savedHistory)) {
            for (let i = 0; i < savedHistory.length && i < root._maxHistory; i++) {
                const e = root._normalizeEntry(savedHistory[i])
                if (e) _history.append(e)
            }
        }
        root._seen = savedSeen && typeof savedSeen === "object" && !Array.isArray(savedSeen) ? savedSeen : ({})
        root._times = savedTimes && typeof savedTimes === "object" && !Array.isArray(savedTimes) ? savedTimes : ({})
        // last: the writes above must not echo back out to disk while restoring
        root._persistentReady = true
    }

    on_SeenChanged:   if (_persistentReady) _persist.seenJson = JSON.stringify(_seen)
    on_TimesChanged:  if (_persistentReady) _persist.timesJson = JSON.stringify(_times)

    function _cloneMap(map): var {
        const out = {}
        if (!map || typeof map !== "object") return out
        for (const k in map) out[k] = map[k]
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

    // when the dwell should start counting: the latest content update, else arrival
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
        // PersistentProperties survives a QML engine replacement. Keep JS
        // arrays/maps serialized so values never cross into the new engine.
        property string historyJson: "[]"
        property string seenJson:  "{}"  // prevents shimmer replay on delegate rebuilds
        property string timesJson: "{}"  // pins arrival timestamps
    }

    signal sourcePulse(int wsId, bool critical)
    // a replacement restarts the dwell; _times keeps the original arrival for the caption
    signal contentUpdated(int notifId)

    readonly property bool _fullscreenWatchWanted: ShellSettings.notifFullscreenSilence
        || ShellSettings.mediaProgress
        || (ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated)
    readonly property bool _fullscreenActive: _fullscreenWatchWanted && Compositor.activeFullscreen
    readonly property bool fullscreenActive: _fullscreenActive
    readonly property bool fullscreenSilenced: ShellSettings.notifFullscreenSilence && _fullscreenActive

    function refreshFullscreenState(): void { Compositor.refreshToplevels() }
    function toggleDnd(): void { dnd = !dnd }

    // auto DND across the quiet-hours window; re-evaluates as the hour rolls (bound int, no timer)
    readonly property bool _quietActive: {
        if (!ShellSettings.dndSchedule) return false
        const from = ShellSettings.dndFrom, to = ShellSettings.dndTo
        if (from === to) return false
        const h = DateTime.hour24
        return from < to ? (h >= from && h < to) : (h >= from || h < to)
    }
    // What actually silences popups: the manual toggle OR a scheduled quiet hour.
    readonly property bool effectiveDnd: dnd || _quietActive
    readonly property bool _silencingActive: effectiveDnd || fullscreenSilenced
    // Clear only after every silencing reason ends. Turning manual DND off
    // during quiet hours, or while fullscreen, must not erase the count early.
    on_SilencingActiveChanged: { if (!_silencingActive && missedCount !== 0) missedCount = 0 }
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
        // The spec marks transient notifications as ineligible for any
        // persistence surface, including Silere's in-memory history.
        if (!notification || notification.transient) return null
        return {
            id:      id,
            appName: notification.appName || "",
            appIcon: notification.appIcon || "",
            desktopEntry: notification.desktopEntry || "",
            summary: root.plainText(notification.summary),
            body:    root.plainText(notification.body),
            urgency: notification.urgency,
            time:    time
        }
    }

    function _historyEntry(e): var {
        if (!e || !e.notification) return null
        return root._notificationHistoryEntry(e.notification, e.id, root._times[e.id] ?? e.time)
    }

    // Insert newest-first, but replace an existing replaces_id snapshot rather
    // than filling history with every progress/message update.
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

    // strip Pango/HTML markup some apps send despite no-markup being advertised
    function plainText(s): string {
        if (!s) return ""
        return String(s)
            .replace(/<\/?(b|i|u|a|span|small|big|tt|markup|sub|sup|s)\b[^>]*>/gi, "")
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ").replace(/&hellip;/g, "…")
            .replace(/&amp;/g, "&")
    }

    // bare absolute paths resolve against the qml context (qrc:/...) and fail to load
    function fileUrl(raw): string {
        const value = String(raw || "").trim()
        return value.startsWith("/") ? "file://" + encodeURI(value) : value
    }

    function resolveIconSource(raw): string {
        const value = String(raw || "").trim()
        if (value.length === 0) return ""
        if (value.startsWith("/")) return root.fileUrl(value)
        if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return value
        return Quickshell.iconPath(value, true)
    }

    function appIconSource(appIcon, desktopEntry, appName): string {
        const direct = root.resolveIconSource(appIcon)
        if (direct.length > 0) return direct
        const identity = String(desktopEntry || appName || "")
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

    function _onClosed(id: int, notification): void {
        if (root._consumeClosing(id, notification)) return
        root._forget(id)
    }

    Component.onCompleted: {
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
        // purge ids that closed while the shell was down
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
        // unset flag makes apps downgrade their content
        imageSupported:       true
        persistenceSupported: true

        onNotification: (n) => {
            root._ensurePersistentState()
            if (root.effectiveDnd && n.urgency !== NotificationUrgency.Critical) {
                // DND suppresses the interruption, not the user's ability to
                // review it later. Replacements update one history entry.
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
            // No popup surface exists at all with popups off, so nothing would ever
            // expire these or write them to history — archive here instead of
            // tracking them forever. Urgency earns no exemption: there is no card
            // for a critical to appear on either.
            if (!ShellSettings.notifPopupEnabled) {
                root._archiveNotification(n, n.id, Date.now())
                n.tracked = false
                return
            }
            // Stamp arrival time once per id; a content update keeps the original.
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
            // a reused object builds no new delegate, so nothing would restart its dwell
            if (existing >= 0 && !isNewObject) root.contentUpdated(n.id)

            if (ShellSettings.wsNotifPulse) {
                const srcWs = HyprActions.notificationSourceWorkspace(n)
                if (srcWs > 0) root.sourcePulse(srcWs, n.urgency === NotificationUrgency.Critical)
            }
        }
    }
}
