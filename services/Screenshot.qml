pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    signal flashed()
    readonly property bool armed: SystemTools.ready

    property real _lastFlashTime: 0

    function flash(): void {
        const now = Date.now()
        if (now - root._lastFlashTime < 300) return
        root._lastFlashTime = now
        root.flashed()
    }

    // Dedup: some tools fire close_write then moved_to for the same filename
    // within a single save; suppress a second flash within 1.5 s.
    property string _lastFile: ""
    property real   _lastTime: 0

    function _maybeFlash(path: string): void {
        const f = String(path || "").trim()
        if (!f || !/\.(png|jpg|jpeg|webp)$/i.test(f)) return
        const now = Date.now()
        if (f === root._lastFile && now - root._lastTime < 1500) return
        root._lastFile = f
        root._lastTime = now
        root.flash()
    }

    SupervisedProcess {
        // The IPC flash remains available unconditionally; the filesystem
        // watcher is only useful when screenshot glow can display its events.
        superviseWhen: SystemTools.ready && SystemTools.hasInotifywait
            && ShellSettings.underlineGlow && ShellSettings.underlineScreenshotGlow
        restartDelay: 60000
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
            "exec inotifywait -m -q -e close_write,moved_to --format '%w%f' \"${dirs[@]}\" 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => root._maybeFlash(line)
        }
    }

    IpcHandler {
        target: "screenshot"
        function flash(): void { root.flash() }
    }
}
