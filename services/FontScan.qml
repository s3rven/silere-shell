pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property list<string> families: []
    // true only after fc-list has exited cleanly, so "no families" can be told apart from "not asked yet"
    property bool scanned: false
    property bool scanning: false
    property string lastError: ""
    property bool _scanned: false

    function scan(force: bool): void {
        if ((!force && _scanned) || !SystemTools.hasFcList || _proc.running) return
        _scanned = true
        scanning = true
        lastError = ""
        _proc.running = true
    }

    function refresh(): void { scan(true) }

    // singletons are lazy: creation means the picker is on screen, and a menu-open signal would have fired before this object existed
    Component.onCompleted: scan(false)
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready) root.scan(false) }
        function onCheckingChanged() {
            if (!SystemTools.checking && SystemTools.ready) root.refresh()
        }
        function onHasFcListChanged() {
            if (SystemTools.hasFcList) {
                if (SystemTools.ready) root.scan(false)
            } else if (SystemTools.ready) {
                if (_proc.running) _proc.running = false
                root._scanned = false
                root.scanned = false
                root.scanning = false
                root.families = []
                root.lastError = ""
            }
        }
    }

    Process {
        id: _proc
        // %{family} not %{family[0]}: fontconfig lists aliases in one comma-separated value, and slot zero drops installed fonts
        command: ["fc-list", "--format", "%{family}\n"]
        stdout: StdioCollector { id: _out }
        onExited: (code) => {
            root.scanning = false
            if (!SystemTools.hasFcList) {
                root._scanned = false
                root.scanned = false
                root.families = []
                root.lastError = ""
                return
            }
            if (code !== 0) {
                root._scanned = false
                root.lastError = "Font scan failed (exit " + code + ")"
                return
            }
            // font family aliases are external input; a null-prototype table keeps names such as "constructor" from colliding with JS built-ins
            const variants = Object.create(null)
            const lines = (_out.text || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const aliases = lines[i].split(",")
                for (let j = 0; j < aliases.length; j++) {
                    const f = aliases[j].trim()
                    const match = /^(.*) Nerd Font(?: (Mono))?$/.exec(f)
                    if (!match || match[1] === "Symbols") continue
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
            root.families = out
            root.scanned = true
            root.lastError = ""
        }
    }
}
