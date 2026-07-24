pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property list<string> families: []
    property bool _scanned: false

    function scan(): void {
        if (_scanned || !SystemTools.hasFcList || _proc.running) return
        _scanned = true
        _proc.running = true
    }

    // singletons are lazy: creation means the picker is on screen, so scan right away —
    // a menu-open signal would have fired before this object existed
    Component.onCompleted: scan()
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready) root.scan() }
    }

    Process {
        id: _proc
        // %{family} is intentionally used instead of %{family[0]}. Fontconfig can
        // expose aliases and style-specific family names in one comma-separated
        // value; reading only slot zero makes installed fonts disappear from the picker.
        command: ["fc-list", "--format", "%{family}\n"]
        stdout: StdioCollector { id: _out }
        onExited: (code) => {
            if (code !== 0) { root._scanned = false; return }
            const variants = {}
            const lines = (_out.text || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const aliases = lines[i].split(",")
                for (let j = 0; j < aliases.length; j++) {
                    const f = aliases[j].trim()
                    const match = /^(.*) Nerd Font(?: (Mono))?$/.exec(f)
                    if (!match || match[1] === "Symbols") continue
                    const base = match[1]
                    const variant = match[2] || "Regular"
                    if (!variants[base]) variants[base] = {}
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
        }
    }
}
