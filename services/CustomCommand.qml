pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "NotificationText.js" as NotificationText
import "../config"

// the bar's command widget: one process for every bar, run only while a command is set and the widget is on, paused
// while idle like the other readings, and never in a test copy, which must not run the user's scripts. Armed at start
// for its IPC target; until a command is set that costs one parsed setting and no process
Singleton {
    id: root

    readonly property bool armed: true
    readonly property var argv: root.expandHome(Settings.splitCommand(ShellSettings.customCommand),
        Quickshell.env("HOME") || "")
    readonly property var clickArgv: root.expandHome(Settings.splitCommand(ShellSettings.customClickCommand),
        Quickshell.env("HOME") || "")
    readonly property bool wanted: ShellSettings.barShowCustom && root.argv.length > 0
        && Quickshell.env("SILERE_SANDBOX") !== "1"
    readonly property int intervalMs: Math.max(5, Math.min(3600, ShellSettings.customInterval)) * 1000
    // a script that floods its output keeps only this much: a few lines are all a reading needs
    readonly property int maxLines: 8
    readonly property int maxLineChars: 8192

    property string text: ""
    property string tooltip: ""
    // 0 plain, 1 warning, 2 critical, from the class names waybar scripts print
    property int level: 0
    property string lastError: ""
    property var _lines: []
    // a script still running a second after its first line is a continuous one, as waybar runs a module with no
    // interval: each line it prints is a reading, until it exits or the command changes. One that prints faster than
    // this is a flood, and stops
    property bool following: false
    readonly property int maxFollowRate: 20
    property int _rateLines: 0
    property bool _flooded: false
    // coalesce refresh requests and wait for a retiring process before starting its replacement
    property bool _refreshAfterExit: false

    // no shell runs the command, so nothing else would turn ~/ into the home directory
    // nor $HOME, which waybar's exec lines use as often as ~ (waybar runs them through sh): each word's leading one
    function expandHome(argv, home: string): var {
        if (argv.length === 0 || home.length === 0) return argv
        return argv.map(word => {
            const w = String(word)
            for (const name of ["~", "$HOME", "${HOME}"])
                if (w === name || w.startsWith(name + "/")) return home + w.slice(name.length)
            return w
        })
    }

    // waybar's custom-module output, so its scripts move over unchanged: a JSON object ({ text, tooltip, class }), or
    // plain lines (text, then tooltip, then class). Markup is dropped as notifications drop it; null when nothing reads
    function parseOutput(raw): var {
        const out = String(raw ?? "").slice(0, root.maxLines * root.maxLineChars)
        const trimmed = out.trim()
        if (trimmed.length === 0) return null
        let text = "", tooltip = "", classes = []
        if (trimmed.startsWith("{")) {
            const object = s => { try { const v = JSON.parse(s); return v && typeof v === "object" && !Array.isArray(v) ? v : null } catch (e) { return null } }
            // one object per run, or a script that prints several: the whole output, else its last complete line
            let data = object(trimmed)
            const lines = trimmed.split("\n").filter(l => l.trim().length > 0)
            for (let i = lines.length - 1; !data && i >= 0; i--) data = object(lines[i])
            if (!data) return null
            text = typeof data.text === "string" || typeof data.text === "number" ? String(data.text) : ""
            tooltip = typeof data.tooltip === "string" ? data.tooltip : ""
            classes = Array.isArray(data["class"]) ? data["class"].filter(c => typeof c === "string")
                : typeof data["class"] === "string" ? [data["class"]] : []
        } else {
            const lines = out.split("\n")
            text = lines[0] ?? ""
            tooltip = lines[1] ?? ""
            classes = String(lines[2] ?? "").trim().split(/\s+/)
        }
        const clean = (s, cap) => SafeText.singleLineText(NotificationText.plainText(String(s)), cap)
        const names = classes.map(c => c.toLowerCase())
        const shown = clean(text, 80)
        if (shown.length === 0) return null
        return {
            text: shown,
            // a tooltip's lines read as one line on the bar
            tooltip: clean(tooltip.split("\n").map(l => l.trim()).filter(l => l.length > 0).join(" · "), 160),
            level: names.some(c => c === "critical" || c === "urgent" || c === "error") ? 2
                : names.some(c => c === "warning" || c === "warn") ? 1 : 0
        }
    }

    function refresh(): void {
        if (!root.wanted) return
        if (_run.running) {
            // re-enabling the widget or waking from idle can beat the old command's exit
            if (_run.stopped) root._refreshAfterExit = true
            return
        }
        root._lines = []
        _run.command = root.argv
        _run.running = true
    }

    function requestRefresh(): void {
        if (!root.wanted) return
        if (_run.running && !root.following) root._refreshAfterExit = true
        else root.refresh()
    }

    function _read(line: string): void {
        // a script may print once more before the stop reaches it: switched off or replaced, that line is not a reading
        if (_run.stopped || !root.wanted) return
        const kept = line.slice(0, root.maxLineChars)
        if (root.following) {
            if (++root._rateLines > root.maxFollowRate) {
                root._flooded = true
                _run.stop()
                return
            }
            root._show(root.parseOutput(kept))
            return
        }
        if (root._lines.length < root.maxLines) root._lines = root._lines.concat([kept])
        // enough for a reading: a flood (`yes`) stops here instead of running a core to the deadline
        if (root._lines.length >= root.maxLines) _run.stop()
        else if (root._lines.length === 1) _followCheck.restart()
    }

    // an empty reading hides the widget, as waybar hides a module whose script printed nothing
    function _show(reading): void {
        root.text = reading ? reading.text : ""
        root.tooltip = reading ? reading.tooltip : ""
        root.level = reading ? reading.level : 0
        root.lastError = ""
    }

    function refreshReply(): string {
        if (!root.wanted) return !ShellSettings.barShowCustom ? "the command widget is off"
            : root.argv.length === 0 ? "no command set" : "a test copy runs no command"
        root.requestRefresh()
        return "ok"
    }
    function statusText(): string {
        return JSON.stringify({ on: root.wanted, text: root.text, tooltip: root.tooltip,
            level: ["normal", "warning", "critical"][root.level] ?? "normal", error: root.lastError,
            continuous: root.following })
    }

    function activate(): void {
        if (root.clickArgv.length === 0) {
            root.requestRefresh()
            return
        }
        SystemTools.runOrNotify(root.clickArgv, "The command widget's click did not start")
        // what the click changed shows once it has had a moment
        _afterClick.restart()
    }

    function _clear(why: string): void {
        if (why.length > 0 && why !== root.lastError) console.warn("silere-shell: the bar's command " + why)
        root.text = ""
        root.tooltip = ""
        root.level = 0
        root.lastError = why
    }

    BoundedProcess {
        id: _run
        // a continuous script runs as long as it prints; only a one-shot run has a deadline
        timeoutMs: root.following ? 0 : 10000
        stdout: SplitParser {
            onRead: line => root._read(String(line))
        }
        onExited: code => {
            const followed = root.following
            const flooded = root._flooded
            root.following = false
            root._flooded = false
            _followCheck.stop()
            if (root._refreshAfterExit) {
                root._refreshAfterExit = false
                Qt.callLater(root.refresh)
                if (_run.stopped) return
            }
            if (!root.wanted) return
            if (flooded) {
                root._clear("printed more than " + root.maxFollowRate + " lines a second")
                return
            }
            // a continuous script that ends keeps its last reading and starts again at the next tick
            if (followed) {
                if (!_run.stopped && code !== 0) root._clear("stopped with code " + code)
                return
            }
            if (!_run.completedSuccessfully(code) && !_run.stopped) {
                // 127: the program is missing or not executable, or one the script runs is
                root._clear(_run.timedOut ? "took longer than 10 s"
                    : code === 127 ? "could not start a program (127)" : "exited with code " + code)
                return
            }
            const reading = root.parseOutput(root._lines.join("\n"))
            if (!reading) {
                root._clear("printed nothing to show")
                return
            }
            root._show(reading)
        }
    }

    Timer {
        id: _followCheck
        interval: 1000
        onTriggered: {
            if (!_run.running || _run.stopped || root._lines.length === 0) return
            root.following = true
            root._refreshAfterExit = false
            root._rateLines = 0
            // what came before is read as one run's output: a one-shot script that prints text, tooltip and class and
            // then lingers keeps its tooltip and colour, and a JSON script's last whole line wins as before
            root._show(root.parseOutput(root._lines.join("\n")))
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.following
        onTriggered: root._rateLines = 0
    }
    // idle stops a continuous script as it pauses the timer; the timer starts it again on the way back
    Connections {
        target: Idle
        function onIsIdleChanged() { if (Idle.isIdle && root.following) _run.stop() }
    }

    Timer {
        interval: root.intervalMs
        running: root.wanted && !Idle.isIdle
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer {
        id: _afterClick
        interval: 600
        onTriggered: root.requestRefresh()
    }

    // waybar's signal: a script that knows its state changed asks for a reading now instead of waiting for the tick
    IpcHandler {
        target: "custom"

        function refresh(): string { return root.refreshReply() }
        function status(): string { return root.statusText() }
    }

    // a new command answers at once, not at the next tick; switched off, its last reading goes with it
    onArgvChanged: {
        if (_run.running) {
            root._refreshAfterExit = root.wanted
            _run.stop()
        } else if (root.wanted) Qt.callLater(root.refresh)
    }
    onWantedChanged: {
        if (root.wanted) return
        root._refreshAfterExit = false
        root._clear("")
        _run.stop()
    }
}
