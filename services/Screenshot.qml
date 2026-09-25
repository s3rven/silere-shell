pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    signal flashed()

    // shell.qml reads this at startup so the IPC handler registers before BarUnderline, the only other reference, loads
    readonly property bool armed: true

    property real _lastFlashTime: 0

    function flash(): void {
        const now = Date.now()
        if (now - root._lastFlashTime < 300) return
        root._lastFlashTime = now
        root.flashed()
    }

    property string _lastFile: ""
    property real   _lastTime: 0

    // the pictures root also holds photos, so only a screenshot-like name flashes there
    property var _pictureRoots: []
    function _screenshotName(name: string): bool {
        return /screen|shot|grim|swappy|satty|spectacle/i.test(name)
            || /^\d{4}-\d{2}-\d{2}[T_ ]\d{2}[:-]\d{2}/.test(name)
    }

    function _maybeFlash(path: string): void {
        const f = String(path || "").trim()
        if (f.startsWith("ROOT ")) {
            if (root._pictureRoots.indexOf(f.slice(5)) < 0)
                root._pictureRoots = root._pictureRoots.concat([f.slice(5)])
            return
        }
        if (!f || !/\.(png|jpg|jpeg|webp)$/i.test(f)) return
        const slash = f.lastIndexOf("/")
        if (root._pictureRoots.indexOf(f.slice(0, slash + 1)) >= 0
                && !root._screenshotName(f.slice(slash + 1))) return
        const now = Date.now()
        if (f === root._lastFile && now - root._lastTime < 1500) return
        root._lastFile = f
        root._lastTime = now
        root.flash()
    }

    // no screenshot directory exists, so the watcher retired and the glow cannot fire
    readonly property bool watcherRetired: _watcher.gaveUp

    function retryWatcher(): void {
        if (_watcher.gaveUp) _watcher.retry()
    }

    Connections {
        target: SystemTools
        function onScanRevisionChanged() {
            if (SystemTools.hasInotifywait) root.retryWatcher()
        }
    }

    SupervisedProcess {
        id: _watcher
        superviseWhen: SystemTools.ready && SystemTools.hasInotifywait
            && ShellSettings.underlineGlow && ShellSettings.underlineScreenshotGlow
        restartDelay: 60000
        // exit 3 means no screenshot directory exists; immediate respawns cannot fix that,
        // but a later explicit tool recheck retries after the user creates one
        giveUpCodes: [3]
        command: ["bash", "-c",
            "dirs=(); " +
            "add_dir() { local d=\"$1\" e; [ -n \"$d\" ] && [ -d \"$d\" ] || return; " +
            "  for e in \"${dirs[@]}\"; do [ \"$e\" = \"$d\" ] && return; done; dirs+=(\"$d\"); }; " +
            "pic=\"${XDG_PICTURES_DIR:-}\"; " +
            "if [ -z \"$pic\" ] && command -v xdg-user-dir >/dev/null 2>&1; then pic=$(xdg-user-dir PICTURES 2>/dev/null || true); fi; " +
            "[ -n \"$pic\" ] || pic=\"$HOME/Pictures\"; " +
            "add_dir \"${HYPRSHOT_DIR:-}\"; " +
            "add_dir \"${GRIM_DEFAULT_DIR:-}\"; " +
            "add_dir \"${SCREENSHOT_DIR:-}\"; " +
            "add_dir \"${XDG_SCREENSHOTS_DIR:-}\"; " +
            "add_dir \"$pic\"; " +
            "add_dir \"$pic/Screenshots\"; " +
            "add_dir \"$HOME/Pictures\"; " +
            "add_dir \"$HOME/Pictures/Screenshots\"; " +
            "add_dir \"$HOME/Screenshots\"; " +
            "add_dir \"$HOME/.nxc/screenshots\"; " +
            "[ \"${#dirs[@]}\" -gt 0 ] || exit 3; " +
            "envd=(\"${HYPRSHOT_DIR:-}\" \"${GRIM_DEFAULT_DIR:-}\" \"${SCREENSHOT_DIR:-}\" \"${XDG_SCREENSHOTS_DIR:-}\"); " +
            "for r in \"$pic\" \"$HOME/Pictures\"; do own=0; " +
            "  for e in \"${envd[@]}\"; do [ -n \"$e\" ] && [ \"${e%/}\" = \"${r%/}\" ] && own=1; done; " +
            "  [ \"$own\" = 1 ] || printf 'ROOT %s/\\n' \"${r%/}\"; done; " +
            // a signal to qs skips its cleanup, so the kernel ends the watcher with it
            "setpriv --pdeathsig KILL true >/dev/null 2>&1 && set -- setpriv --pdeathsig KILL || set --; " +
            "exec \"$@\" inotifywait -m -q -e close_write,moved_to --format '%w%f' \"${dirs[@]}\" 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => root._maybeFlash(line)
        }
    }

    IpcHandler {
        target: "screenshot"
        function flash(): void { root.flash() }
    }
}
