pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// installed-font inventory for the font picker; one fc-list pass on first use, zero idle cost
Singleton {
    id: root

    // non-Propo Nerd families only: the bar renders Nerd glyphs from the same face as labels,
    // so anything else breaks the icons. Mono twins are hidden when the regular variant exists.
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
    // instantiation can race the tool scan; catch up once it lands
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready) root.scan() }
    }

    Process {
        id: _proc
        command: ["fc-list", "--format", "%{family[0]}\n"]
        stdout: StdioCollector { id: _out }
        onExited: (code) => {
            if (code !== 0) { root._scanned = false; return }
            const seen = {}
            const lines = (_out.text || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const f = lines[i].trim()
                if (!/ Nerd Font( Mono)?$/.test(f)) continue
                if (f === "Symbols Nerd Font" || f === "Symbols Nerd Font Mono") continue   // icon-only, no text glyphs
                seen[f] = true
            }
            const out = []
            for (const f in seen) {
                if (f.endsWith(" Nerd Font Mono") && seen[f.slice(0, -5)]) continue
                out.push(f)
            }
            out.sort()
            root.families = out
        }
    }
}
