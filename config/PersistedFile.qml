pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// the write ladder every config file shares: coalesce a burst into one write, wait for the
// config dir, back off on failure, and never write over a file we could not read
Scope {
    id: root

    property string path
    property bool watchChanges: false
    property int debounceMs: 400
    property int maxRetries: 3

    // owners clear this on a bad read: a file we could not parse may still hold data this session never saw
    property bool writeAllowed: true
    property int failureCount: 0
    property string lastSavedText: ""
    property bool _pendingForDir: false

    // owner-supplied, returns the text to persist
    property var serialize: null

    readonly property bool pending: _debounce.running || _retry.running

    signal loaded(string raw)
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)

    function queue(): void {
        ConfigStore.ensureDirectory()
        _debounce.restart()
    }

    function stop(): void {
        _debounce.stop()
        _retry.stop()
    }

    function flush(force: bool): void {
        if (!root.writeAllowed || !root.serialize) return
        if (!force && !ConfigStore.ready) {
            root._pendingForDir = true
            ConfigStore.ensureDirectory()
            return
        }
        const text = root.serialize()
        if (typeof text !== "string") return
        if (text === root.lastSavedText) return
        root._pendingForDir = false
        root.lastSavedText = text
        // alternate trailing whitespace: FileView coalesces identical setText() calls, so an exact retry never reaches the disk
        _file.setText(text + (root.failureCount % 2 === 0 ? "\n" : "\n\n"))
    }

    Timer { id: _debounce; interval: root.debounceMs; onTriggered: root.flush(false) }
    Timer {
        id: _retry
        interval: Math.min(8000, 1000 * Math.pow(2, Math.max(0, root.failureCount - 1)))
        onTriggered: root.flush(false)
    }

    Connections {
        target: ConfigStore
        function onReadyChanged() {
            if (ConfigStore.ready && root._pendingForDir) {
                root._pendingForDir = false
                root.flush(false)
            }
        }
    }

    FileView {
        id: _file
        path: root.path
        watchChanges: root.watchChanges
        atomicWrites: true
        blockWrites:  true
        printErrors:  false
        onLoaded: root.loaded(_file.text() || "")
        onFileChanged: reload()
        onLoadFailed: error => root.loadFailed(error)
        onSaved: {
            root.failureCount = 0
            _retry.stop()
            root.saved()
        }
        onSaveFailed: error => {
            // clear the candidate on failure, or the same text stays mistaken for an already-persisted value forever
            root.lastSavedText = ""
            root.failureCount++
            if (root.failureCount <= root.maxRetries) _retry.restart()
            root.saveFailed(error)
        }
    }
}
