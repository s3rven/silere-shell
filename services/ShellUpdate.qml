pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Self-update state for the shell itself (distinct from Updates.qml, which counts
// distro packages). The daily timer's update.sh runs check-only and drops a flag
// file when origin/main is ahead; this watches that flag via inotify (no polling)
// so a pending update surfaces in the bar instead of a surprise mid-session restart.
Singleton {
    id: root

    property int    count: 0
    property string summary: ""
    property bool   applying: false

    readonly property bool pending: count > 0
    readonly property string label: count + (count === 1 ? " new commit" : " new commits")

    readonly property string _cacheDir: {
        const env = Quickshell.env("XDG_CACHE_HOME")
        const base = (env && String(env).length > 0)
            ? String(env)
            : String(Quickshell.env("HOME")) + "/.cache"
        return base + "/silere-shell"
    }
    readonly property string _script: Quickshell.shellDir + "/scripts/update.sh"

    function apply(): void {
        if (applying || !pending) return
        applying = true
        _applyTimeout.restart()
        Quickshell.execDetached(["bash", root._script, "--apply"])
    }

    // execDetached is fire-and-forget; if --apply fails we never see it, so clear
    // the applying state ourselves rather than leave the bar stuck on "updating…"
    Timer {
        id: _applyTimeout
        interval: 30000
        onTriggered: root.applying = false
    }

    FileView {
        id: _flag
        path: root._cacheDir + "/update-pending"
        watchChanges: true
        printErrors:  false
        onLoaded:     root._parse(_flag.text())
        onLoadFailed: { root.count = 0; root.summary = ""; _applyTimeout.stop(); root.applying = false }
        onFileChanged: reload()
    }

    function _parse(t: string): void {
        const lines = (t || "").split(/\r?\n/)
        const n = parseInt((lines[0] || "").trim())
        root.count = isNaN(n) ? 0 : n
        root.summary = lines.slice(1).join("\n").trim()
    }
}
