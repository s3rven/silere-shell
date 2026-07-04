pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var list: []
    property alias history:     _persist.history
    property alias dnd:         _persist.dnd
    property alias missedCount: _persist.missedCount
    property alias _seen:       _persist.seen
    property alias _times:      _persist.times
    readonly property int _maxHistory: 20
    readonly property int activeCount: Array.isArray(list) ? list.length : 0
    readonly property int historyCount: Array.isArray(history) ? history.length : 0
    readonly property bool hasHistory: historyCount > 0

    // popups use the live ObjectModel so new cards don't cause a full Repeater rebuild
    readonly property var popupModel: notifServer.trackedNotifications

    function _ensurePersistentState(): void {
        // var properties can be undefined for one frame during hot-reload
        if (!Array.isArray(_persist.history)) _persist.history = []
        if (!_persist.seen || typeof _persist.seen !== "object") _persist.seen = ({})
        if (!_persist.times || typeof _persist.times !== "object") _persist.times = ({})
    }

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
    }

    function timeFor(id: int): real {
        return root._ensureTime(id)
    }

    // track object not just id — replaces_id reuses ids while old closed signal is pending
    property var _closing: ({})
    property bool lastCritical: false

    PersistentProperties {
        id: _persist
        reloadableId: "silereNotifications"
        property var  history: []
        property bool dnd: false
        property int  missedCount: 0
        // seen prevents shimmer replay on delegate rebuilds; times pins arrival stamps
        property var  seen:  ({})
        property var  times: ({})
    }

    signal sourcePulse(int wsId, bool critical)

    onDndChanged: { if (!dnd && missedCount !== 0) missedCount = 0 }

    property bool _fullscreenActive: false
    readonly property bool fullscreenActive: _fullscreenActive
    readonly property bool fullscreenSilenced: ShellSettings.notifFullscreenSilence && _fullscreenActive

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "fullscreen" || n === "activewindow" || n === "workspace"
                || n === "focusedmon" || n === "closewindow")
                _fsRefresh.restart()
        }
    }
    Timer {
        id: _fsRefresh
        interval: 100
        onTriggered: {
            Hyprland.refreshToplevels()
            const o = Hyprland.activeToplevel ? Hyprland.activeToplevel.lastIpcObject : null
            root._fullscreenActive = !!(o && o.fullscreen)
        }
    }

    function toggleDnd(): void { dnd = !dnd }
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
        if (history.length === 0) return
        for (let i = 0; i < history.length; i++) {
            const id = history[i]?.id
            if (id !== undefined) root._forgetState(id)
        }
        history = []
    }

    function _historyEntry(e): var {
        if (!e || !e.notification) return null
        return {
            id:      e.id,
            appName: e.notification.appName || "",
            summary: root.plainText(e.notification.summary),
            body:    root.plainText(e.notification.body),
            urgency: e.notification.urgency,
            time:    root._times[e.id] ?? e.time
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

    // strip Pango/HTML markup some apps send despite no-markup being advertised
    function plainText(s) {
        if (!s) return ""
        return String(s)
            .replace(/<\/?(b|i|u|a|span|small|big|tt|markup|sub|sup|s)\b[^>]*>/gi, "")
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ").replace(/&hellip;/g, "…")
            .replace(/&amp;/g, "&")
    }

    function removeFromHistory(entry): void {
        const idx = (typeof entry === "number")
            ? entry
            : history.findIndex(h => h.time === entry.time && h.summary === entry.summary)
        if (idx < 0 || idx >= history.length) return
        const next = [...history]
        const id = next.splice(idx, 1)[0]?.id
        history = next
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
        if (entry) history = [entry, ...history].slice(0, _maxHistory)
        root._forget(notifId)
    }

    function _onClosed(id: int, notification): void {
        if (root._consumeClosing(id, notification)) return
        root._forget(id)
    }

    function dismissAll(): void {
        if (list.length === 0) return
        const entries = []
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            const entry = root._historyEntry(e)
            if (entry) entries.unshift(entry)
            if (e && e.notification) {
                root._markClosing(e.id, e.notification)
                e.notification.dismiss()
            }
        }
        _seen = {}
        _times = {}
        list = []
        if (lastCritical) lastCritical = false
        if (entries.length > 0)
            history = [...entries, ...history].slice(0, _maxHistory)
    }

    Component.onCompleted: {
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
        _fsRefresh.restart()
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
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
                root.missedCount++
                n.tracked = false
                return
            }
            if (root.fullscreenSilenced && n.urgency !== NotificationUrgency.Critical) {
                root.history = [{
                    appName: n.appName || "",
                    summary: root.plainText(n.summary),
                    body:    root.plainText(n.body),
                    urgency: n.urgency,
                    time:    Date.now()
                }, ...root.history].slice(0, root._maxHistory)
                root.missedCount++
                n.tracked = false
                return
            }
            // Stamp arrival time once per id; a content update keeps the original.
            const arrivalTime = root._ensureTime(n.id)
            root.lastCritical = n.urgency === NotificationUrgency.Critical

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

            if (ShellSettings.wsNotifPulse) {
                const srcWs = HyprActions.notificationSourceWorkspace(n)
                if (srcWs > 0) root.sourcePulse(srcWs, n.urgency === NotificationUrgency.Critical)
            }
        }
    }
}
