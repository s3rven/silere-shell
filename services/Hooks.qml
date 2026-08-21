pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string directory: ConfigStore.directory.length > 0
        ? ConfigStore.directory + "/hooks" : ""

    // the scan probes these names rather than listing the directory, so a file
    // dropped there under any other name is never a path this can execute
    readonly property var events: [
        "battery-critical",
        "notification",
        "theme-changed",
        "update-available",
        "workspace-changed"
    ]

    readonly property int maxArgChars: 512
    readonly property int maxArgs: 4

    readonly property int maxRunsPerSecond: 20

    property var _present: ({})
    property var _found: ({})
    property bool _scanned: false
    property var _runTimes: []
    property bool _throttled: false
    readonly property bool armed: true

    function has(event: string): bool {
        return root._present[event] === true
    }

    // a notification flood or a workspace event storm reaches here once per event;
    // without a ceiling each one is another spawn
    function _budgetAllows(): bool {
        const now = Date.now()
        const recent = []
        for (let i = 0; i < root._runTimes.length; i++)
            if (now - root._runTimes[i] < 1000) recent.push(root._runTimes[i])
        if (recent.length >= root.maxRunsPerSecond) {
            root._runTimes = recent
            return false
        }
        recent.push(now)
        root._runTimes = recent
        return true
    }

    function fire(event: string, args): void {
        if (root._present[event] !== true) return
        if (!root._budgetAllows()) {
            if (!root._throttled) {
                root._throttled = true
                console.warn("silere-shell: hooks exceeded "
                    + root.maxRunsPerSecond + " runs/s; dropping until it settles")
            }
            return
        }
        root._throttled = false
        const argv = [root.directory + "/" + event]
        const list = args || []
        const n = Math.min(list.length, root.maxArgs)
        for (let i = 0; i < n; i++)
            argv.push(SafeText.singleLineText(String(list[i]), root.maxArgChars))
        Quickshell.execDetached(argv)
    }

    function rescan(): void {
        if (root.directory.length === 0 || _scan.running) return
        root._found = ({})
        _scan.running = true
    }

    Process {
        id: _scan
        command: ["bash", "-c",
            "d=\"$1\"; shift; cd -- \"$d\" 2>/dev/null || exit 0; "
            + "for f in \"$@\"; do [ -f \"$f\" ] && [ -x \"$f\" ] "
            + "&& printf '%s\\n' \"$f\"; done",
            "bash", root.directory].concat(root.events)
        // every write to _present rebinds all five hook targets; collect, then swap once
        stdout: SplitParser {
            onRead: line => {
                const name = line.trim()
                if (root.events.indexOf(name) < 0) return
                root._found[name] = true
            }
        }
        onExited: {
            root._present = Object.assign({}, root._found)
            root._found = ({})
            root._scanned = true
        }
    }

    Connections {
        target: ConfigStore
        function onReadyChanged() {
            if (ConfigStore.ready) root.rescan()
        }
    }

    // an unset hook leaves its target out of the binding entirely, so a service
    // nothing else has built is not created just to be watched
    Connections {
        target: root._present["notification"] === true ? Notifications : null
        function onNotificationShown(appName, summary, critical) {
            root.fire("notification", [appName, summary, critical ? "critical" : "normal"])
        }
    }

    Connections {
        target: root._present["battery-critical"] === true ? Battery : null
        function onCriticalChanged() {
            if (Battery.critical) root.fire("battery-critical", [Battery.pct])
        }
    }

    // the accent rails write per pointer frame; fire on the colour the drag lands on
    Timer {
        id: _accentSettle
        interval: 400
        onTriggered: root.fire("theme-changed", [String(Theme.accent)])
    }

    Connections {
        target: root._present["theme-changed"] === true ? Theme : null
        function onAccentChanged() { _accentSettle.restart() }
    }

    Connections {
        target: root._present["update-available"] === true ? Updates : null
        function onCountChanged() {
            if (Updates.count > 0) root.fire("update-available", [Updates.count])
        }
    }

    Connections {
        target: root._present["workspace-changed"] === true ? Compositor : null
        // niri's ref is an internal id; wsId is the number on screen on both backends
        function onFocusedWorkspaceRefChanged() {
            root.fire("workspace-changed",
                [Compositor.activeWorkspaceId(Compositor.focusedMonitor)])
        }
    }

    Component.onCompleted: if (ConfigStore.ready) root.rescan()

    IpcHandler {
        target: "hooks"

        function list(): string {
            if (root.directory.length === 0) return "no configuration directory"
            const out = []
            for (let i = 0; i < root.events.length; i++) {
                const e = root.events[i]
                out.push((root._present[e] === true ? "active  " : "unset   ") + e)
            }
            return root.directory + "\n" + out.join("\n")
        }

        function rescan(): string {
            root.rescan()
            return "ok"
        }
    }
}
