pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int  count: 0
    property int  repoCount: 0
    property int  aurCount: 0
    // rebuilt only on a completed check, never bound per frame; capped so a long-neglected system can't build a huge model
    property var  packages: []
    readonly property int _maxDetail: 80
    property bool ready: false
    property bool lastFailed: false
    property string lastError: ""
    property real lastCheckMs: 0
    property bool _timedOut: false

    readonly property bool enabled: ShellSettings.updatesWidget
    readonly property bool _online: !Network.toolAvailable || Network.connected

    readonly property string manager: {
        if (!SystemTools.ready) return ""
        switch (SystemTools.packageFamily) {
        case "pacman":
            if (SystemTools.hasCheckupdates) return "pacman"
            if (SystemTools.hasParu || SystemTools.hasYay) return "aur"
            return ""
        case "apt":    return SystemTools.hasApt ? "apt" : ""
        case "dnf":    return SystemTools.hasDnf ? "dnf" : ""
        case "zypper": return SystemTools.hasZypper ? "zypper" : ""
        case "xbps":   return SystemTools.hasXbps ? "xbps" : ""
        }
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
        : !SystemTools.ready ? "Detecting"
        : !supported ? "Unsupported"
        : ready ? (count > 0 ? label : "Up to date")
        : "Waiting"

    function _limit(seconds: int, command: string): string {
        return SystemTools.hasTimeout ? ("timeout " + seconds + " " + command) : command
    }

    function _cmd(): string {
        switch (root.manager) {
        case "pacman": {
            // checkupdates self-syncs to a private db; rc 2 = no updates, and ERR holds the last count so a network blip can't zero the badge
            const aur = SystemTools.hasParu ? root._limit(60, "paru -Qua") + " 2>/dev/null"
                      : SystemTools.hasYay  ? root._limit(60, "yay -Qua") + " 2>/dev/null"
                      : "true"
            return "out=$(" + root._limit(90, "checkupdates") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ \"$rc\" -ne 2 ]; then echo \"ERR checkupdates failed (exit $rc)\"; exit 0; fi; " +
                   "aurout=$(" + aur + "); " +
                   "repo=$(printf '%s' \"$out\" | grep -c .); " +
                   "aur=$(printf '%s' \"$aurout\" | grep -c .); " +
                   "echo $((repo + aur)); " +
                   "echo \"SPLIT $repo $aur\"; " +
                   "printf '%s\\n' \"$out\"; printf '%s\\n' \"$aurout\""
        }
        case "aur": {
            const tool = SystemTools.hasParu ? "paru" : "yay"
            return "out=$(" + root._limit(90, tool + " -Qu") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ -n \"$out\" ]; then echo \"ERR " + tool + " check failed (exit $rc)\"; exit 0; fi; " +
                   "printf '%s' \"$out\" | grep -c .; " +
                   "printf '%s\\n' \"$out\""
        }
        case "apt":    return "out=$(" + root._limit(120, "apt list --upgradable") + " 2>&1); rc=$?; " +
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

    // checkupdates and paru -Qua both print "name oldver -> newver"; anything else stays a bare count
    function _parseDetail(text: string): void {
        const lines = text.split("\n")
        let repo = -1, aur = -1, start = 1
        const split = lines.length > 1 ? lines[1].trim() : ""
        if (split.startsWith("SPLIT ")) {
            const p = split.split(/\s+/)
            repo = parseInt(p[1]); aur = parseInt(p[2])
            start = 2
        }
        // repo lines come first, then AUR; budget for the AUR tail so a long repo list can't crowd it out
        const repoBudget = Math.max(0, root._maxDetail - Math.max(0, aur))
        const out = []
        let seen = 0, repoShown = 0
        for (let i = start; i < lines.length && out.length < root._maxDetail; i++) {
            const parts = lines[i].trim().split(/\s+/)
            if (parts.length < 4 || parts[2] !== "->") continue
            const isAur = repo >= 0 && seen >= repo
            seen++
            if (!isAur) {
                if (repoShown >= repoBudget) continue
                repoShown++
            }
            out.push({ name: parts[0], from: parts[1], to: parts[3], aur: isAur })
        }
        root.repoCount = repo >= 0 ? repo : root.count
        root.aurCount  = aur  >= 0 ? aur  : 0
        root.packages  = out
    }

    function refresh(): void {
        // read the setting directly — on a manual toggle the `enabled` alias may not have re-evaluated yet
        if (!ShellSettings.updatesWidget || !supported || _proc.running) return
        root._timedOut = false
        _proc.exec(["bash", "-c", root._cmd()])
    }

    function _resetDisabledState(): void {
        _initDelay.stop()
        _retry.stop()
        _reconnect.stop()
        if (_proc.running) _proc.running = false
        root.count = 0
        root.repoCount = 0
        root.aurCount = 0
        root.packages = []
        root.ready = true
        root.lastFailed = false
        root.lastError = ""
    }

    Process {
        id: _proc
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _out }
        onExited: {
            if (root._timedOut) return
            root.lastCheckMs = Date.now()
            if (!ShellSettings.updatesWidget) {
                root._resetDisabledState()
                return
            }
            const t = (_out.text || "").trim()
            const n = parseInt(t)
            if (!t.startsWith("ERR") && !isNaN(n)) {
                root.count = n
                root._parseDetail(t)
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

    Timer {
        interval: 180000
        running: _proc.running
        onTriggered: {
            root._timedOut = true
            root.lastCheckMs = Date.now()
            root.lastFailed = true
            root.lastError = "Package check timed out"
            root.ready = true
            _retry.restart()
            _proc.running = false
        }
    }

    Timer {
        id: _poll
        interval: 900000
        repeat:   true
        running:  root.enabled && root.supported && !Idle.isIdle && root._online
        onTriggered: root.refresh()
    }

    Timer { id: _retry; interval: 180000; onTriggered: if (root._online) root.refresh() }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle || !root.enabled || !root.supported || !root._online) return
            if (Date.now() - root.lastCheckMs >= _poll.interval) root.refresh()
        }
    }

    Timer { id: _reconnect; interval: 5000; onTriggered: root.refresh() }
    Connections {
        target: Network
        function onConnectedChanged() {
            if (Network.connected && root.enabled && root.supported && root.lastFailed)
                _reconnect.restart()
        }
    }

    Timer { id: _initDelay; interval: 8000; onTriggered: root.refresh() }

    onSupportedChanged:    if (root.enabled) _initDelay.restart()
    Component.onCompleted: if (root.enabled && root.supported) _initDelay.restart()
    Connections {
        target: ShellSettings
        function onUpdatesWidgetChanged() {
            if (ShellSettings.updatesWidget) root.refresh()
            else root._resetDisabledState()
        }
    }
}
