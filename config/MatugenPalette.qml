pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// the singleton itself is shipped and immutable. Matugen writes only the small
// per-user JSON palette below, which also works when Silere lives in /usr/share
Singleton {
    id: root

    readonly property string _directory: XdgPaths.configHome.length > 0
        ? XdgPaths.configHome + "/matugen" : ""
    readonly property string palettePath: _directory.length > 0 ? _directory + "/silere-shell.json" : ""

    property var _palette: ({})
    property bool _everLoaded: false
    property string _loadState: "loading"
    readonly property string loadState: root._loadState
    readonly property bool usingFallback: !root._everLoaded
    readonly property bool paletteStale: root._everLoaded && root.loadState !== "ready"
    readonly property var _fallback: ({
        background: "#101116",
        surface:    "#1d1f26",
        text:       "#e9eaf0",
        subtext:    "#a0a4b0",
        accent:     "#9babe9",
        error:      "#dd92a2",
        warning:    "#d4ad77",
        success:    "#94bd8b"
    })
    readonly property var _roles: [
        "background", "surface", "text", "subtext",
        "accent", "error", "warning", "success"
    ]

    readonly property color background: _palette.background ?? _fallback.background
    readonly property color surface:    _palette.surface    ?? _fallback.surface
    readonly property color text:       _palette.text       ?? _fallback.text
    readonly property color subtext:    _palette.subtext    ?? _fallback.subtext
    readonly property color accent:     _palette.accent     ?? _fallback.accent
    readonly property color error:      _palette.error      ?? _fallback.error
    readonly property color warning:    _palette.warning    ?? _fallback.warning
    readonly property color success:    _palette.success    ?? _fallback.success

    function _parsePalette(raw: string): var {
        let parsed
        try {
            parsed = JSON.parse(raw || "")
        } catch (e) {
            return null
        }
        if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object")
            return null
        const clean = Object.create(null)
        for (let i = 0; i < root._roles.length; i++) {
            const role = root._roles[i]
            const value = parsed[role]
            if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value))
                return null
            clean[role] = value.toLowerCase()
        }
        return clean
    }

    function _load(raw: string): void {
        const parsed = root._parsePalette(raw)
        // keep the last valid palette during an editor save or atomic replace; a malformed external file must never partially recolor the shell
        if (parsed === null) {
            root._loadState = "invalid"
            return
        }
        if (root._roles.some(role => parsed[role] !== root._palette[role]))
            root._palette = parsed
        root._everLoaded = true
        root._loadState = "ready"
    }

    function reload(): void {
        if (root.palettePath.length > 0) _paletteFile.reload()
    }

    readonly property FileView _paletteView: _paletteFile
    FileView {
        id: _paletteFile
        path: root.palettePath
        watchChanges: true
        printErrors: false
        onLoaded: root._load(_paletteFile.text() || "")
        onFileChanged: _settle.restart()
        onLoadFailed: error => {
            root._loadState = error === FileViewError.FileNotFound ? "missing" : "unreadable"
        }
    }

    // a file watch cannot see through a missing parent, and a watch on the parent fires for every change in the config home
    property bool _directoryFound: false
    onLoadStateChanged: if (root.loadState !== "missing") root._directoryFound = false
    FileView {
        id: _directoryWatch
        path: root.loadState === "missing" ? root._directory : ""
        watchChanges: path.length > 0 && !root._directoryFound
        printErrors: false
        onFileChanged: _directoryWatch.reload()
        onLoadFailed: error => {
            // NotAFile means the directory exists. Recheck after installing the watch
            // in case the palette was written while the watcher was being set up
            if (path.length === 0 || error !== FileViewError.NotAFile) return
            root._directoryFound = true
            _settle.restart()
        }
    }

    Connections {
        target: root.loadState === "missing" ? ConfigStore : null
        // the shell can create XDG_CONFIG_HOME after the initial watch attempt
        function onReadyChanged() {
            if (ConfigStore.ready && root._directory.length > 0) _directoryWatch.reload()
        }
    }

    Timer {
        id: _settle
        interval: 80
        onTriggered: root.reload()
    }
}
