pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Pending-package counter. Off unless ShellSettings.updatesWidget is on, since the
// check does background package-DB work. Distro-agnostic: the first available
// manager wins; pacman pulls in AUR updates too when paru/yay is present.
Singleton {
    id: root

    property int  count: 0
    property bool ready: false
    // Last check errored (network down, mirror hung). The count is held and a
    // faster retry is armed instead of waiting out the full poll.
    property bool lastFailed: false
    property string lastError: ""
    property real lastCheckMs: 0

    readonly property bool enabled: ShellSettings.updatesWidget
    // assume online when there's no nmcli to ask
    readonly property bool _online: !Network.toolAvailable || Network.connected

    readonly property string manager: {
        if (!SystemTools.ready) return ""
        if (SystemTools.hasCheckupdates) return "pacman"
        if (SystemTools.hasParu || SystemTools.hasYay) return "aur"
        if (SystemTools.hasApt)          return "apt"
        if (SystemTools.hasDnf)          return "dnf"
        if (SystemTools.hasZypper)       return "zypper"
        if (SystemTools.hasXbps)         return "xbps"
        return ""
    }
    readonly property bool   supported:  manager.length > 0
    readonly property bool   available:  enabled && supported && count > 0
    readonly property bool   isChecking: _proc.running
    readonly property string icon:      (manager === "pacman" || manager === "aur") ? "󰮯" : "󰚰"
    readonly property string label:     count + (count === 1 ? " update" : " updates")
    readonly property string managerLabel: {
        switch (manager) {
        case "pacman":
            if (SystemTools.hasParu) return "pacman + paru"
            if (SystemTools.hasYay)  return "pacman + yay"
            return "pacman"
        case "aur":    return SystemTools.hasParu ? "paru" : "yay"
        case "apt":    return "apt"
        case "dnf":    return "dnf"
        case "zypper": return "zypper"
        case "xbps":   return "xbps"
        }
        return SystemTools.ready ? "Unsupported" : "Detecting..."
    }
    readonly property string statusText: isChecking ? "Checking"
        : lastFailed ? "Check failed"
        : !enabled ? "Disabled"
        : !supported ? "Unsupported"
        : ready ? (count > 0 ? label : "Up to date")
        : "Waiting"

    function _limit(seconds: int, command: string): string {
        return SystemTools.hasTimeout ? ("timeout " + seconds + " " + command) : command
    }

    function _cmd(): string {
        switch (root.manager) {
        case "pacman": {
            // checkupdates self-syncs to a private db (no root, no touch to the
            // system db); rc 2 just means "no updates". Any real failure prints
            // ERR so a network blip holds the last count instead of zeroing the
            // badge; timeout caps a hung mirror sync.
            const aur = SystemTools.hasParu ? root._limit(60, "paru -Qua") + " 2>/dev/null | grep -c ."
                      : SystemTools.hasYay  ? root._limit(60, "yay -Qua") + " 2>/dev/null | grep -c ."
                      : "echo 0"
            return "out=$(" + root._limit(90, "checkupdates") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ \"$rc\" -ne 2 ]; then echo \"ERR checkupdates failed (exit $rc)\"; exit 0; fi; " +
                   "repo=$(printf '%s' \"$out\" | grep -c .); " +
                   "aur=$(" + aur + "); " +
                   "echo $((repo + aur))"
        }
        // AUR helper without checkupdates: -Qu counts repo + AUR against the
        // last-synced db. No fresh sync, but far better than "unsupported".
        case "aur": {
            const tool = SystemTools.hasParu ? "paru" : "yay"
            return "out=$(" + root._limit(90, tool + " -Qu") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ -n \"$out\" ]; then echo \"ERR " + tool + " check failed (exit $rc)\"; exit 0; fi; " +
                   "printf '%s\\n' \"$out\" | grep -c ."
        }
        case "apt":    return "out=$(apt list --upgradable 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR apt check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c /"
        case "dnf":    return "out=$(" + root._limit(120, "dnf -q check-update") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ] && [ \"$rc\" -ne 100 ]; then echo \"ERR dnf check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -cE '^[a-zA-Z0-9]'"
        case "zypper": return "out=$(" + root._limit(120, "zypper -q list-updates") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR zypper check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c '^v '"
        case "xbps":   return "out=$(" + root._limit(120, "xbps-install -Mun") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR xbps check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c ."
        }
        return "echo 0"
    }

    function refresh(): void {
        // Read the setting directly: on a manual toggle the `enabled` alias may
        // not have re-evaluated yet.
        if (!ShellSettings.updatesWidget || !supported || _proc.running) return
        _proc.exec(["bash", "-c", root._cmd()])
    }

    function _resetDisabledState(): void {
        _initDelay.stop()
        _retry.stop()
        _reconnect.stop()
        if (_proc.running) _proc.running = false
        root.count = 0
        root.ready = true
        root.lastFailed = false
        root.lastError = ""
    }

    Process {
        id: _proc
        stdout: StdioCollector { id: _out }
        onExited: {
            root.lastCheckMs = Date.now()
            if (!ShellSettings.updatesWidget) {
                root._resetDisabledState()
                return
            }
            const t = (_out.text || "").trim()
            const n = parseInt(t)
            if (!t.startsWith("ERR") && !isNaN(n)) {
                root.count = n
                root.lastFailed = false
                root.lastError = ""
            } else {
                root.lastFailed = true
                root.lastError = t.startsWith("ERR") ? t.substring(3).trim() : "Package check returned no count"
                _retry.restart()
            }
            root.ready = true
        }
    }

    // 15 min: responsive without hammering mirrors (checkupdates does a conditional
    // db sync each run) or the AUR RPC. Click the widget to force a check sooner.
    // Paused while offline; the reconnect hook below catches up.
    Timer {
        id: _poll
        interval: 900000
        repeat:   true
        running:  root.enabled && root.supported && !Idle.isIdle && root._online
        onTriggered: root.refresh()
    }

    // failed check → retry in 3 min instead of waiting out the full poll
    Timer { id: _retry; interval: 180000; onTriggered: if (root._online) root.refresh() }

    // Idle pauses the poll, and waking restarts its full interval — after a
    // long screen-off the count could be hours stale. Catch up once on wake.
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle || !root.enabled || !root.supported || !root._online) return
            if (Date.now() - root.lastCheckMs >= _poll.interval) root.refresh()
        }
    }

    // Back online after a failed check: refresh once the link settles, so the
    // badge recovers in seconds rather than at the next poll.
    Timer { id: _reconnect; interval: 5000; onTriggered: root.refresh() }
    Connections {
        target: Network
        function onConnectedChanged() {
            if (Network.connected && root.enabled && root.supported && root.lastFailed)
                _reconnect.restart()
        }
    }

    // Startup with the setting already on: defer the first check so it isn't
    // competing with login I/O. A manual toggle (below) checks right away instead.
    Timer { id: _initDelay; interval: 8000; onTriggered: root.refresh() }

    onSupportedChanged:    if (root.enabled) _initDelay.restart()
    Component.onCompleted: if (root.enabled && root.supported) _initDelay.restart()
    Connections {
        target: ShellSettings
        function onUpdatesWidgetChanged() {
            if (ShellSettings.updatesWidget) root.refresh()   // immediate feedback on enable
            else root._resetDisabledState()                    // hide the widget at once when off
        }
    }
}
