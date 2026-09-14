pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    // the history list model, and the counter it bumps when its contents move
    property var source: null
    property int revision: 0
    property string filter: ""

    readonly property alias model: _rows
    readonly property int count: _rows.count

    // the reconcile edits only the rows that differ, and these count the edits it made:
    // an arrival the filter excludes has to leave the drawn rows untouched
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
        return e ? [e.id, e.time, e.urgency, e.appName, e.appIcon,
                    e.desktopEntry, e.summary, e.body].join("\u0001") : ""
    }

    function _copy(e): var {
        return { id: e.id, appName: e.appName, appIcon: e.appIcon,
                 desktopEntry: e.desktopEntry, summary: e.summary,
                 body: e.body, urgency: e.urgency, time: e.time }
    }

    function sync(): void {
        const src = root.source
        const want = root.filter
        const rows = []
        for (let i = 0; src && i < src.count; i++) {
            const e = src.get(i)
            if (!e) continue
            if (want.length === 0 || root.identityOf(e.appName) === want) rows.push(e)
        }
        const keys = rows.map(e => root._key(e))
        const live = Object.create(null)
        for (let i = 0; i < keys.length; i++) live[keys[i]] = true

        for (let i = _rows.count - 1; i >= 0; i--) {
            if (live[root._key(_rows.get(i))]) continue
            _rows.remove(i)
            root.removes++
        }
        for (let i = 0; i < rows.length; i++) {
            if (i < _rows.count && root._key(_rows.get(i)) === keys[i]) continue
            _rows.insert(i, root._copy(rows[i]))
            root.inserts++
        }
        while (_rows.count > rows.length) {
            _rows.remove(_rows.count - 1)
            root.removes++
        }
    }

    onSourceChanged: root.sync()
    onRevisionChanged: root.sync()
    onFilterChanged: root.sync()
    Component.onCompleted: root.sync()
}
