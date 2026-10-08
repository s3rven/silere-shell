pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    // the history list model, and the counter it bumps when its contents move
    property var source: null
    property int revision: 0
    property string filter: ""
    property string query: ""
    property bool active: true

    readonly property alias model: _rows
    readonly property int count: _rows.count

    // the reconcile edits only the rows that differ, and these count the edits it made: an arrival the filter excludes has to leave the drawn rows untouched
    property int inserts: 0
    property int removes: 0

    width: 0
    height: 0
    visible: false

    ListModel { id: _rows }

    // history normalizes a name on the way in, so the rail's key is this trim
    function identityOf(name): string {
        const trimmed = String(name ?? "").trim()
        return trimmed.length > 0 ? trimmed : "Unknown"
    }

    // keyed by content, not position: an id and a time both survive an in-place update,
    // so a row whose text changed has to miss the match and be rebuilt on its own
    function _key(e): string {
        // stored rows are replaced, never edited in place, so their key stays valid
        if (e && typeof e.contentKey === "string") return e.contentKey
        return e ? [e.id, e.time, e.urgency, e.appName, e.appIcon,
                    e.desktopEntry, e.summary, e.body].join("\u0001") : ""
    }

    function _copy(e): var {
        return { id: e.id, appName: e.appName, appIcon: e.appIcon,
                 desktopEntry: e.desktopEntry, summary: e.summary,
                 body: e.body, urgency: e.urgency, time: e.time }
    }

    // on the row, not the delegate: a neighbour read through get() never reports its changes
    function _row(e, key: string): var {
        const r = root._copy(e)
        r.contentKey = key
        r.first = false
        r.showSection = false
        r.groupStart = false
        r.groupEnd = false
        return r
    }

    function _dayKey(ms): int {
        const d = new Date(Number(ms))
        return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate()
    }

    function _flag(row, i: int, role: string, value: bool): void {
        if (row[role] !== value) _rows.setProperty(i, role, value)
    }

    // a critical row stands alone so its red outline is never shared with a run
    function _syncFlags(): void {
        const n = _rows.count
        let prev = null
        let prevDay = 0
        let prevName = ""
        let prevCritical = false
        for (let i = 0; i < n; i++) {
            const e = _rows.get(i)
            const day = root._dayKey(e.time)
            const name = root.identityOf(e.appName)
            const critical = Number(e.urgency) === 2
            const section = !prev || prevDay !== day
            const start = section || prevName !== name || critical || prevCritical
            root._flag(e, i, "first", i === 0)
            root._flag(e, i, "showSection", section)
            root._flag(e, i, "groupStart", start)
            if (prev) root._flag(prev, i - 1, "groupEnd", start)
            prev = e
            prevDay = day
            prevName = name
            prevCritical = critical
        }
        if (prev) root._flag(prev, n - 1, "groupEnd", true)
    }

    function snapshot(): var {
        const entries = []
        for (let i = 0; i < _rows.count; i++) entries.push(root._copy(_rows.get(i)))
        return entries
    }

    function sync(): void {
        if (!root.active) return
        const src = root.source
        const want = root.filter
        const terms = root.query.trim().toLowerCase().split(/\s+/).filter(t => t.length > 0)
        const rows = []
        for (let i = 0; src && i < src.count; i++) {
            const e = src.get(i)
            if (!e) continue
            if (want.length > 0 && root.identityOf(e.appName) !== want) continue
            if (terms.length > 0) {
                const text = [root.identityOf(e.appName), e.summary, e.body].join(" ").toLowerCase()
                if (!terms.every(term => text.indexOf(term) >= 0)) continue
            }
            rows.push(e)
        }
        const keys = rows.map(e => root._key(e))
        const live = Object.create(null)
        for (let i = 0; i < keys.length; i++) live[keys[i]] = true

        let changed = false
        for (let i = _rows.count - 1; i >= 0; i--) {
            if (live[root._key(_rows.get(i))]) continue
            _rows.remove(i)
            root.removes++
            changed = true
        }
        for (let i = 0; i < rows.length; i++) {
            if (i < _rows.count && root._key(_rows.get(i)) === keys[i]) continue
            _rows.insert(i, root._row(rows[i], keys[i]))
            root.inserts++
            changed = true
        }
        while (_rows.count > rows.length) {
            _rows.remove(_rows.count - 1)
            root.removes++
            changed = true
        }
        // Excluded arrivals and an unchanged query leave every grouping flag valid.
        if (changed) root._syncFlags()
    }

    onSourceChanged: root.sync()
    onRevisionChanged: root.sync()
    onFilterChanged: root.sync()
    onQueryChanged: root.sync()
    onActiveChanged: root.sync()
    Component.onCompleted: root.sync()
}
