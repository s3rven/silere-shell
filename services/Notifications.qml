pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var list: []
    // History, DND, and bookkeeping survive shell reloads (PersistentProperties);
    // a config tweak + reload no longer wipes the notification archive.
    property alias history:     _persist.history
    property alias dnd:         _persist.dnd
    property alias missedCount: _persist.missedCount
    property alias _seen:       _persist.seen
    property alias _times:      _persist.times
    readonly property int _maxHistory: 20
    readonly property int activeCount: list.length
    readonly property int historyCount: history.length
    readonly property bool hasHistory: historyCount > 0

    // popups use the live ObjectModel so new cards don't cause a full Repeater rebuild
    readonly property var popupModel: notifServer.trackedNotifications

    function timeFor(id: int): real { return root._times[id] || Date.now() }

    // Notification objects we're tearing down ourselves. Track the object, not just
    // the id: replaces_id can reuse an id while an old object's closed signal is
    // still pending, and id-only guards can then skip/remove the wrong live entry.
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

    // Emitted when a notification arrives whose source window sits on workspace
    // wsId, so the Workspaces widget can pulse that dot. critical picks the tint.
    signal sourcePulse(int wsId, bool critical)

    onDndChanged: { if (!dnd && missedCount !== 0) missedCount = 0 }

    // ── Fullscreen silence ────────────────────────────────────────────────
    // While the focused window is fullscreen, non-critical notifications skip
    // the popup and archive straight to history. Event-driven: the relevant
    // Hyprland events refresh the toplevel cache, then the active window's
    // fullscreen flag is re-read — this also covers switching workspaces away
    // from (or back to) a fullscreen window, which fires no fullscreen event.
    property bool _fullscreenActive: false
    readonly property bool fullscreenSilenced: ShellSettings.notifFullscreenSilence && _fullscreenActive

    Connections {
        target: Hyprland
        enabled: ShellSettings.notifFullscreenSilence
        function onRawEvent(event) {
            const n = event.name
            if (n === "fullscreen" || n === "activewindow" || n === "workspace"
                || n === "focusedmon" || n === "closewindow")
                _fsRefresh.restart()
        }
    }
    Connections {
        target: ShellSettings
        function onNotifFullscreenSilenceChanged() {
            if (ShellSettings.notifFullscreenSilence) _fsRefresh.restart()
            else root._fullscreenActive = false
        }
    }
    Timer { id: _fsRefresh; interval: 50; onTriggered: { Hyprland.refreshToplevels(); _fsSettle.restart() } }
    // settle delay so the refreshed IPC data has landed before reading it
    Timer {
        id: _fsSettle
        interval: 80
        onTriggered: {
            const o = Hyprland.activeToplevel ? Hyprland.activeToplevel.lastIpcObject : null
            root._fullscreenActive = !!(o && o.fullscreen)
        }
    }

    function toggleDnd(): void { dnd = !dnd }
    function markSeen(id: int): void { _seen[id] = true }
    function isSeen(id: int):   bool { return !!_seen[id] }

    function clearHistory(): void {
        if (history.length > 0) history = []
    }

    function _historyEntry(e): var {
        if (!e || !e.notification) return null
        return {
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
        delete _seen[id]
        delete _times[id]
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

    function removeFromHistory(index: int): void {
        if (index < 0 || index >= history.length) return
        const next = [...history]
        next.splice(index, 1)
        history = next
    }

    function dismissObject(notifId: int, notification): void {
        const n = list.find(e => e.id === notifId && e.notification === notification)
        if (!n) return
        const entry = root._historyEntry(n)
        root._markClosing(notifId, n.notification)
        n.notification.tracked = false
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
                e.notification.tracked = false
            }
        }
        _seen = {}
        _times = {}
        list = []
        if (lastCritical) lastCritical = false
        if (entries.length > 0)
            history = [...entries, ...history].slice(0, _maxHistory)
    }

    // Rebuild the active list from the server's kept-on-reload notifications, so
    // activeCount / dismiss-all stay correct across a shell reload instead of
    // resetting to zero while the popups live on.
    Component.onCompleted: {
        const vals = notifServer.trackedNotifications.values ?? []
        const rebuilt = []
        const live = {}
        for (let i = 0; i < vals.length; i++) {
            const n = vals[i]
            if (!n) continue
            if (root._times[n.id] === undefined) root._times[n.id] = Date.now()
            live[n.id] = true
            rebuilt.push({ notification: n, id: n.id, time: root._times[n.id] })
            n.closed.connect(() => root._onClosed(n.id, n))
        }
        if (rebuilt.length > 0) root.list = rebuilt
        // _seen/_times persist across reloads; drop ids whose notifications
        // closed while the shell was down, or they accumulate forever.
        for (const id in root._seen)  if (!live[id]) delete root._seen[id]
        for (const id in root._times) if (!live[id]) delete root._times[id]
    }

    NotificationServer {
        id: notifServer
        keepOnReload:       true
        bodySupported:      true
        bodyMarkupSupported: false
        actionsSupported:   true

        onNotification: (n) => {
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
                root.missedCount++
                n.tracked = false
                return
            }
            // Fullscreen silence: no popup, but archived so nothing is lost.
            if (root.fullscreenSilenced && n.urgency !== NotificationUrgency.Critical) {
                root.history = [{
                    appName: n.appName || "",
                    summary: root.plainText(n.summary),
                    body:    root.plainText(n.body),
                    urgency: n.urgency,
                    time:    Date.now()
                }, ...root.history].slice(0, _maxHistory)
                n.tracked = false
                return
            }
            // Stamp arrival time once per id; a content update keeps the original.
            if (root._times[n.id] === undefined) root._times[n.id] = Date.now()
            root.lastCritical = n.urgency === NotificationUrgency.Critical

            // Replace existing notification with same id if it's an update
            const existing = root.list.findIndex(e => e.id === n.id)
            // Reuse of the same object (in-place update) is already tracked and
            // wired; only a new object needs the old torn down + a fresh handler.
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
                root.list = [...root.list, { notification: n, id: n.id, time: root._times[n.id] }]
            }
            // Reap our state if the app/server closes this one later. Connect once
            // per object; a stacked handler would fire _onClosed twice for one close.
            if (isNewObject) n.closed.connect(() => root._onClosed(n.id, n))
            // Track last so the popup delegate is created after time/list are ready.
            n.tracked = true

            if (ShellSettings.wsNotifPulse) {
                const srcWs = HyprActions.notificationSourceWorkspace(n)
                if (srcWs > 0) root.sourcePulse(srcWs, n.urgency === NotificationUrgency.Critical)
            }
        }
    }
}
