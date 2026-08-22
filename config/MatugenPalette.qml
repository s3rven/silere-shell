pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The singleton itself is shipped and immutable. Matugen writes only the small
// per-user JSON palette below, which also works when Silere lives in /usr/share.
Singleton {
    id: root

    readonly property string palettePath: {
        const configured = String(Quickshell.env("XDG_CONFIG_HOME") || "").trim()
        if (configured.startsWith("/")) return configured + "/matugen/silere-shell.json"
        const home = String(Quickshell.env("HOME") || "").trim()
        return home.startsWith("/") ? home + "/.config/matugen/silere-shell.json" : ""
    }

    property var _palette: ({})
    property bool _everLoaded: false
    readonly property bool usingFallback: !root._everLoaded
    // a later bad write keeps the last good colors, which is right, but then nothing
    // moves on screen and usingFallback stays false — the shell has to say why
    property bool paletteStale: false
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
            clean[role] = value
        }
        return clean
    }

    function _load(raw: string): void {
        const parsed = root._parsePalette(raw)
        // keep the last valid palette during an editor save or atomic replace; a malformed external file must never partially recolor the shell
        if (parsed === null) {
            root.paletteStale = root._everLoaded
            return
        }
        root._palette = parsed
        root._everLoaded = true
        root.paletteStale = false
    }

    function _markUnreadable(): void {
        // missing on first launch is the normal bundled fallback. Disappearing after a good load means the colors on screen are now a retained copy
        root.paletteStale = root._everLoaded
    }

    FileView {
        id: _paletteFile
        path: root.palettePath
        watchChanges: true
        printErrors: false
        onLoaded: root._load(_paletteFile.text() || "")
        onFileChanged: reload()
        onLoadFailed: root._markUnreadable()
    }
}
