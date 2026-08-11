pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int maxIdentityChars: 512
    readonly property int maxSourceChars: 4096
    readonly property var _scheme: /^([a-z][a-z0-9+.-]*):/i

    function boundedText(value, limit): string {
        const requested = Number(limit)
        const cap = isFinite(requested) && requested > 0
            ? Math.min(root.maxIdentityChars, Math.floor(requested))
            : root.maxIdentityChars
        const text = String(value ?? "")
        return text.length <= cap ? text : text.slice(0, Math.max(0, cap - 1)) + "…"
    }

    function _fileUrl(value: string): string {
        return "file://" + value.split("/").map(function(part) {
            return encodeURIComponent(part)
        }).join("/")
    }

    // Icon and image fields can originate in any notification or StatusNotifier
    // sender. Keep local files and Qt's internal providers, but never let a label
    // silently turn the shell into a network client or feed it an unbounded data URI.
    function localSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length === 0 || value.length > root.maxSourceChars) return ""
        if (value.startsWith("/")) return root._fileUrl(value)
        const match = root._scheme.exec(value)
        if (!match) return ""
        const scheme = match[1].toLowerCase()
        if (scheme === "file") {
            const path = value.slice(match[0].length)
            // A file URL with an authority can name a remote host. Accept only
            // the two local absolute forms Qt understands: file:/x and file:///x.
            const localAbsolute = path.startsWith("///")
                ? !path.startsWith("////")
                : path.startsWith("/") && !path.startsWith("//")
            return localAbsolute ? value : ""
        }
        return scheme === "qrc" || scheme === "image" ? value : ""
    }

    function iconSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length === 0 || value.length > root.maxSourceChars) return ""
        if (value.startsWith("/") || root._scheme.test(value))
            return root.localSource(value)
        return root.localSource(Quickshell.iconPath(value, true))
    }

    function appMeta(identity): var {
        const original = root.boundedText(identity, root.maxIdentityChars).trim()
        if (original.length === 0) return null

        const noDesktop = original.toLowerCase().endsWith(".desktop")
            ? original.slice(0, -8) : original
        const lower = noDesktop.toLowerCase()
        const parts = lower.split(".").filter(Boolean)
        const tail = parts.length > 0 ? parts[parts.length - 1] : lower
        const entry = DesktopEntries.heuristicLookup(original)
            || DesktopEntries.heuristicLookup(noDesktop)
        const candidates = [
            entry && entry.icon,
            noDesktop,
            lower,
            tail
        ]
        let icon = ""
        for (let i = 0; i < candidates.length && icon.length === 0; i++)
            if (candidates[i]) icon = root.iconSource(candidates[i])

        const name = root.boundedText((entry && entry.name) || tail || noDesktop, 128)
        const fallback = name.length > 0 ? name.charAt(0).toUpperCase() : "?"
        return { icon: icon, name: name, fallback: fallback }
    }
}
