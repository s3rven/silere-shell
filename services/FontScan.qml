pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property list<string> families: []
    property list<string> iconFamilies: []
    // true only after fc-list has exited cleanly, so "no families" can be told apart from "not asked yet"
    property bool scanned: false
    property bool scanning: false
    property string lastError: ""
    property bool _scanned: false
    property bool _refreshPending: false
    property int _generation: 0
    property int _scanGeneration: 0
    // fc-list is a startup process spawn the default font does not need; run it only once something on screen asks for the list
    property bool _wanted: false
    property real _startedAt: 0

    function scan(force: bool): void {
        if (!SystemTools.hasFcList) return
        if (_proc.running) {
            if (force) root._refreshPending = true
            return
        }
        if (!force && _scanned) return
        root._refreshPending = false
        root._scanGeneration = root._generation
        _scanned = true
        root._startedAt = Date.now()
        scanning = true
        lastError = ""
        _proc.running = true
    }

    function requestScan(): void {
        root._wanted = true
        root.scan(false)
    }
    // the first request scans; a later one rescans for newly installed fonts once the last scan is this old
    function refreshIfStale(maxAgeMs: int): void {
        root.requestScan()
        const age = Date.now() - root._startedAt
        if (root.scanned && !(age >= 0 && age < maxAgeMs)) root.scan(true)
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready && root._wanted) root.scan(false) }
        // a completed tool probe can change fc-list availability, but it does not invalidate a list already collected
        function onCheckingChanged() {
            if (!SystemTools.checking && SystemTools.ready && root._wanted) root.scan(false)
        }
        function onHasFcListChanged() {
            root._generation++
            if (SystemTools.hasFcList) {
                if (SystemTools.ready && root._wanted) root.scan(false)
            } else if (SystemTools.ready) {
                root._refreshPending = false
                if (_proc.running) _proc.running = false
                root._scanned = false
                root.scanned = false
                root.scanning = false
                root.families = []
                root.iconFamilies = []
                root.lastError = ""
            }
        }
    }

    BoundedProcess {
        id: _proc
        timeoutMs: 20000
        // %{family} not %{family[0]}: fontconfig lists aliases in one comma-separated value, and slot zero drops installed fonts
        command: ["fc-list", "--format", "%{family}\n"]
        stdout: StdioCollector { id: _out }
        onExited: (code) => {
            root.scanning = false
            const refreshPending = root._refreshPending
            root._refreshPending = false
            if (refreshPending && SystemTools.hasFcList) Qt.callLater(root.scan, true)
            if (!SystemTools.hasFcList) {
                root._scanned = false
                root.scanned = false
                root.families = []
                root.iconFamilies = []
                root.lastError = ""
                return
            }
            if (root._scanGeneration !== root._generation) {
                root._scanned = false
                if (root._wanted) Qt.callLater(root.scan, true)
                return
            }
            if (!_proc.completedSuccessfully(code)) {
                root._scanned = false
                root.lastError = _proc.timedOut ? "Font scan timed out"
                    : "Font scan failed (exit " + code + ")"
                return
            }
            // font family aliases are external input; a null-prototype table keeps names such as "constructor" from colliding with JS built-ins
            const variants = Object.create(null)
            const all = Object.create(null)
            const lines = (_out.text || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const aliases = lines[i].split(",")
                for (let j = 0; j < aliases.length; j++) {
                    const f = aliases[j].trim()
                    if (f.length > 0) all[f] = true
                    const match = /^(.*) Nerd Font(?: (Mono))?$/.exec(f)
                    if (!match) continue
                    const base = match[1]
                    const variant = match[2] || "Regular"
                    if (!variants[base]) variants[base] = Object.create(null)
                    variants[base][variant] = f
                }
            }
            const out = []
            for (const base in variants) {
                const family = variants[base]
                if (family.Regular) out.push(family.Regular)
                else if (family.Mono) out.push(family.Mono)
            }
            out.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
            root.iconFamilies = out
            root.families = Object.keys(all).sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
            root.scanned = true
            root.lastError = ""
        }
    }
}
