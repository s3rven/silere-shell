pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int maxIdentityChars: 512
    readonly property int maxSourceChars: 4096
    readonly property var _scheme: /^([a-z][a-z0-9+.-]*):/i

    function _fileUrl(value: string): string {
        return "file://" + value.split("/").map(function(part) {
            return encodeURIComponent(part)
        }).join("/")
    }

    // image://icon/<name> is filesystem-backed and reads a raw "?path=" segment with no
    // traversal check; only Quickshell's in-memory handles are safe to take from raw text
    readonly property var _imageScheme: /^image:/i
    function _isSafeImageProvider(value: string): bool {
        // qt matches scheme and provider id case-insensitively, so the guard folds case too
        const authority = value.slice(6).replace(/^\/\//, "").toLowerCase()
        return authority === "qsimage" || authority === "qspixmap"
            || authority.startsWith("qsimage/") || authority.startsWith("qspixmap/")
    }

    // a tray item's icon arrives from Quickshell as image://icon/<name>?path=<dir>, so
    // refusing the provider outright leaves every app shipping its own icons unrendered
    function _isSafeIconProvider(value: string): bool {
        const rest = value.slice(6).replace(/^\/\//, "")
        if (rest.slice(0, 5).toLowerCase() !== "icon/") return false
        const q = rest.indexOf("?")
        const name = q < 0 ? rest : rest.slice(0, q)
        if (name.length <= 5 || name.indexOf("/", 5) >= 0) return false
        if (q < 0) return true
        const query = rest.slice(q + 1)
        if (query.slice(0, 5).toLowerCase() !== "path=") return false
        let dir = ""
        try { dir = decodeURIComponent(query.slice(5)) } catch (e) { return false }
        // the segment the guard was written for: an absolute directory that cannot climb out
        return dir.startsWith("/") && ("/" + dir + "/").indexOf("/../") < 0
    }

    function safeLocalSource(raw): string {
        const source = root.localSource(raw)
        return root._imageScheme.test(source) && !root._isSafeImageProvider(source) ? "" : source
    }

    // the tray's icons come from Quickshell's own SystemTray service, not from raw sender
    // text, and image://icon is the only form it offers for an app shipping its own theme
    function trayIconSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length === 0 || value.length > root.maxSourceChars) return ""
        if (root._imageScheme.test(value))
            return root._isSafeImageProvider(value) || root._isSafeIconProvider(value)
                ? value : ""
        return root.iconSource(value)
    }

    function trayAppIconSource(raw, identity): string {
        const source = root.trayIconSource(raw)
        return source.length > 0 ? source : (root.appMeta(identity)?.icon ?? "")
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
            // a file URL with an authority can name a remote host. Accept only the two local absolute forms Qt understands: file:/x and file:///x
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
        // raw text skips the theme-existence check iconPath() applies below, so an image: URI only passes here as Quickshell's safe in-memory handle
        if (value.startsWith("/") || root._scheme.test(value))
            return root.safeLocalSource(value)
        return root.localSource(Quickshell.iconPath(value, true))
    }

    function senderImageSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length > root.maxSourceChars) return ""
        if (value.startsWith("/") || /^file:/i.test(value)) return root._systemIconFile(value)
        // notify-send sends -i as the image-path hint, which quickshell rewrites to image://icon/<value>
        const hinted = /^image:(?:\/\/)?icon\/([^?]*)$/i.exec(value)
        if (hinted) {
            const name = hinted[1]
            if (name.startsWith("/")) return root._systemIconFile(name)
            return name.length > 0 && name.indexOf("/") < 0 ? root.iconSource(name) : ""
        }
        const source = root.localSource(value)
        if (source.startsWith("qrc:")) return source
        return root._imageScheme.test(source) && root._isSafeImageProvider(source) ? source : ""
    }

    // only root can create files here, so a sender cannot plant a fifo or device node behind an icon path
    readonly property var _systemIconRoots: ["/usr/share/icons/", "/usr/share/pixmaps/",
        "/usr/local/share/icons/", "/usr/local/share/pixmaps/", "/var/lib/flatpak/exports/share/icons/"]

    function _systemIconFile(value: string): string {
        let path = value
        if (/^file:/i.test(path)) {
            if (!/^file:\/\/\//i.test(path) || /^file:\/\/\/\//i.test(path)) return ""
            try { path = decodeURIComponent(path.slice(7)) } catch (e) { return "" }
        }
        if (("/" + path + "/").indexOf("/../") >= 0 || ("/" + path + "/").indexOf("/./") >= 0) return ""
        return root._systemIconRoots.some(prefix => path.startsWith(prefix)) ? root._fileUrl(path) : ""
    }

    function senderIconSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length > root.maxSourceChars) return ""
        if (value.startsWith("/")) return root._systemIconFile(value)
        const match = root._scheme.exec(value)
        if (match && match[1].toLowerCase() === "file") return root._systemIconFile(value)
        return root.iconSource(value)
    }

    function appMeta(identity): var {
        const original = SafeText.boundedText(identity, root.maxIdentityChars).trim()
        if (original.length === 0) return null

        const noDesktop = original.toLowerCase().endsWith(".desktop")
            ? original.slice(0, -8) : original
        const lower = noDesktop.toLowerCase()
        // only a reverse-DNS id (org.gnome.Nautilus) names the app in its last part; "Minecraft* 1.21.1" would name it "1"
        const tailOf = s => /^[a-z][a-z0-9-]*(\.[a-z0-9_-]+){2,}$/i.test(s)
            ? s.slice(s.lastIndexOf(".") + 1) : s.replace(/\.exe$/i, "")
        const tail = tailOf(lower)
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

        const name = SafeText.singleLineText((entry && entry.name) || tailOf(noDesktop) || noDesktop, 128)
        return { icon: icon, name: name, fallback: SafeText.initial(name, "?") }
    }
}
