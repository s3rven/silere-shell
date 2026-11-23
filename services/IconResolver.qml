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
    function isMemoryImage(source): bool {
        const value = String(source ?? "")
        return root._imageScheme.test(value) && root._isSafeImageProvider(value)
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
        if (root._imageScheme.test(value)) {
            if (root._isSafeImageProvider(value)) return value
            if (!root._isSafeIconProvider(value)) return ""
            // a theme name the theme lacks loads Quickshell's magenta and black "missing" squares, not an error, so the
            // app's own icon or its initial never took over. One the app ships in its own folder (?path=) is looked up there
            const bare = /^image:(?:\/\/)?icon\/([^?]+)$/i.exec(value)
            return bare && Quickshell.iconPath(bare[1], true).length === 0 ? "" : value
        }
        return root.iconSource(value)
    }

    function trayAppIconSource(raw, identity): string {
        const source = root.trayIconSource(raw)
        return source.length > 0 ? source : (root.appMeta(identity)?.icon ?? "")
    }

    // QIcon's own factor: the largest screen ratio, which Wayland reports as the whole output scale (2 for a 1.25 screen)
    readonly property real screenScale: {
        let scale = 1
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            scale = Math.max(scale, screens[i]?.devicePixelRatio ?? 1)
        return scale
    }

    function isThemeIcon(source): bool {
        return /^image:(\/\/)?icon\//i.test(String(source ?? ""))
    }

    // the sourceSize that decodes an icon at its device size: Qt Quick scales an image: or SVG request by the window ratio
    // and QIcon scales a theme icon's again by iconScale, so a 16px tray icon at 1.25 was a 50px texture squeezed into 20
    function decodeSide(source, logical: real, dpr: real, iconScale: real): int {
        const ratio = dpr > 0 ? dpr : 1
        const device = Math.max(1, Math.round(logical * ratio))
        const url = String(source ?? "")
        if (root.isThemeIcon(url)) return Math.max(1, Math.round(device / (ratio * Math.max(1, iconScale))))
        if (/^image:/i.test(url) || /\.svgz?(\?.*)?$/i.test(url)) return Math.max(1, Math.round(device / ratio))
        return device
    }

    // a provider that stopped scaling twice hands back about 1/iconScale of the side it was asked for
    function themeScaleMissing(source, implicitSide: real, logical: real, dpr: real, iconScale: real): bool {
        if (!(iconScale > 1) || !root.isThemeIcon(source) || !(implicitSide > 0)) return false
        const ratio = dpr > 0 ? dpr : 1
        return implicitSide * ratio * 1.5 < Math.round(logical * ratio)
    }

    // icon and image fields can originate in any notification or StatusNotifier
    // sender. Keep local files and Qt's internal providers, but never let a label
    // silently turn the shell into a network client or feed it an unbounded data URI
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
        // a name from an app or a desktop file: quickshell numbers its own images in order, so a handle named here is another app's, or after a restart whatever took the number
        if (root.isMemoryImage(value)) return ""
        // raw text skips the theme-existence check iconPath() applies below
        if (value.startsWith("/") || root._scheme.test(value))
            return root.safeLocalSource(value)
        return root.localSource(Quickshell.iconPath(value, true))
    }

    // notify-send sends -i as the image-path hint, which quickshell rewrites to image://icon/<value>
    readonly property var _hintedIcon: /^image:(?:\/\/)?icon\/([^?]*)$/i

    // that hint's icon, for a history entry, which keeps no image: a theme name, or a path senderIconSource
    // still holds to the system icon folders
    function hintedIconName(raw): string {
        const value = String(raw ?? "").trim()
        const hinted = value.length <= root.maxSourceChars ? root._hintedIcon.exec(value) : null
        const name = hinted ? hinted[1] : ""
        return name.startsWith("/") || name.indexOf("/") < 0 ? name : ""
    }

    function senderImageSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length > root.maxSourceChars) return ""
        if (value.startsWith("/") || /^file:/i.test(value)) return root._systemIconFile(value)
        const hinted = root._hintedIcon.exec(value)
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
    readonly property var _systemIconRoots: ["/usr/share/", "/usr/lib/", "/usr/lib64/",
        "/usr/local/share/icons/", "/usr/local/share/pixmaps/", "/var/lib/flatpak/exports/share/icons/",
        "/run/current-system/sw/share/"]

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

    // a game Proton runs is the window class steam_app_<id>, and Steam installs its icon as steam_icon_<id>
    function steamGameIcon(identity: string): string {
        const game = /^steam_app_(\d+)$/i.exec(String(identity || ""))
        return game ? "steam_icon_" + game[1] : ""
    }

    // a game's own Steam shortcut first: the fuzzy lookup could take Steam itself
    function appEntry(identity: string): var {
        const steamIcon = root.steamGameIcon(identity)
        const game = steamIcon.length > 0
            ? (DesktopEntries.applications.values || []).find(e => e && e.icon === steamIcon) : null
        return game || DesktopEntries.heuristicLookup(identity)
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
        const steamIcon = root.steamGameIcon(lower)
        const entry = root.appEntry(original) || DesktopEntries.heuristicLookup(noDesktop)
        const candidates = [
            entry && entry.icon,
            steamIcon,
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
