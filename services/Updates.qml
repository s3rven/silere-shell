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
    property bool _discardResult: false
    // a check fails for a night offline as readily as for a wedged package database;
    // only a failure that outlives a retry says the checker itself is broken
    property int  _failStreak: 0
    property real _nowMs: 0

    readonly property bool enabled: ShellSettings.updatesWidget
    readonly property bool _online: !Network.toolAvailable || Network.connected
    readonly property bool aurHelperAvailable: SystemTools.hasParu || SystemTools.hasYay

    readonly property string manager: {
        if (!SystemTools.ready) return ""
        switch (SystemTools.packageFamily) {
        case "pacman":
            if (SystemTools.hasCheckupdates) return "pacman"
            if (ShellSettings.updatesIncludeAur && root.aurHelperAvailable) return "aur"
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
    readonly property bool   checkBroken: enabled && supported && lastFailed && _failStreak >= 2
    readonly property bool   isChecking: _proc.running
    readonly property string icon:      (manager === "pacman" || manager === "aur") ? "󰮯" : "󰚰"
    readonly property string label:     count + (count === 1 ? " update" : " updates")
    readonly property string managerLabel: {
        switch (manager) {
        case "pacman":
            if (ShellSettings.updatesIncludeAur && SystemTools.hasParu) return "pacman + paru"
            if (ShellSettings.updatesIncludeAur && SystemTools.hasYay)  return "pacman + yay"
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
    readonly property string lastCheckedText: DateTime.agoText(lastCheckMs, _nowMs)
    readonly property string lastCheckLabel: lastCheckedText.length > 0
        ? "Checked " + lastCheckedText : ""

    function _touchNow(): void { root._nowMs = Date.now() }

    Timer {
        interval: 60000
        repeat: true
        running: MenuState.settingsActive && MenuState.settingsSection === "updates"
        onTriggered: root._touchNow()
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._touchNow() }
        function onSettingsSectionChanged() { root._touchNow() }
    }

    function _limit(seconds: int, command: string): string {
        return SystemTools.hasTimeout ? ("timeout " + seconds + " " + command) : command
    }

    function _countFrom(text: string): int {
        const first = String(text ?? "").split("\n")[0].trim()
        // the count line is emitted by our own wrapper. Reject partial parses, signs and implausibly large values before they reach geometry or AT
        if (!/^[0-9]{1,6}$/.test(first)) return -1
        const value = Number(first)
        return isFinite(value) && value <= 100000 ? value : -1
    }

    function _safeError(value): string {
        return SafeText.singleLineText(value, 512)
    }

    function _cmd(): string {
        switch (root.manager) {
        case "pacman": {
            // checkupdates self-syncs to a private db; rc 2 = no updates, and ERR holds the last count so a network blip can't zero the badge
            const aur = ShellSettings.updatesIncludeAur && SystemTools.hasParu
                      ? root._limit(60, "paru -Qua") + " 2>/dev/null"
                      : ShellSettings.updatesIncludeAur && SystemTools.hasYay
                      ? root._limit(60, "yay -Qua") + " 2>/dev/null"
                      : "true"
            return "out=$(" + root._limit(90, "checkupdates") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ \"$rc\" -ne 2 ]; then echo \"ERR checkupdates failed (exit $rc)\"; exit 0; fi; " +
                   "aurout=$(" + aur + "); " +
                   "repo=$(printf '%s' \"$out\" | grep -c .); " +
                   "aur=$(printf '%s' \"$aurout\" | grep -c .); " +
                   "echo $((repo + aur)); " +
                   "echo \"SPLIT $repo $aur\"; " +
                   "printf '%s\\n' \"$out\" | head -n " + root._maxDetail + "; " +
                   "echo \"DETAIL AUR\"; " +
                   "printf '%s\\n' \"$aurout\" | head -n " + root._maxDetail
        }
        case "aur": {
            const tool = SystemTools.hasParu ? "paru" : "yay"
            return "out=$(" + root._limit(90, tool + " -Qu") + " 2>&1); rc=$?; " +
                   "if [ \"$rc\" -ne 0 ] && [ -n \"$out\" ]; then echo \"ERR " + tool + " check failed (exit $rc)\"; exit 0; fi; " +
                   "printf '%s' \"$out\" | grep -c .; " +
                   "printf '%s\\n' \"$out\" | head -n " + root._maxDetail
        }
        case "apt":    return "out=$(" + root._limit(120, "apt list --upgradable") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR apt check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c /; " +
                              "printf '%s\\n' \"$out\" | head -n " + (root._maxDetail + 4)
        case "dnf":    return "out=$(" + root._limit(120, "dnf -q check-update") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ] && [ \"$rc\" -ne 100 ]; then echo \"ERR dnf check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | awk 'NF == 3 && $1 ~ /\\./ { n++ } END { print n + 0 }'; " +
                              "printf '%s\\n' \"$out\" | head -n " + (root._maxDetail + 8)
        case "zypper": return "out=$(" + root._limit(120, "zypper -q list-updates") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR zypper check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c '^v '; " +
                              "printf '%s\\n' \"$out\" | head -n " + (root._maxDetail + 4)
        case "xbps":   return "out=$(" + root._limit(120, "xbps-install -Mun") + " 2>&1); rc=$?; " +
                              "if [ \"$rc\" -ne 0 ]; then echo \"ERR xbps check failed (exit $rc)\"; exit 0; fi; " +
                              "printf '%s\\n' \"$out\" | grep -c .; " +
                              "printf '%s\\n' \"$out\" | head -n " + root._maxDetail
        }
        return "echo 0"
    }

    function _detail(out, name, from, to, aur): void {
        if (out.length >= root._maxDetail) return
        const safeName = SafeText.singleLineText(name, 256)
        const safeFrom = SafeText.singleLineText(from, 128)
        const safeTo = SafeText.singleLineText(to, 128)
        if (safeName.length === 0 || safeTo.length === 0) return
        out.push({ name: safeName, from: safeFrom, to: safeTo, aur: aur === true })
    }

    function _parseDetail(text: string): void {
        const lines = text.split("\n")
        let repo = -1, aur = -1, start = 1
        const split = lines.length > 1 ? lines[1].trim() : ""
        if (split.startsWith("SPLIT ")) {
            const p = split.split(/\s+/)
            const r = parseInt(p[1]), a = parseInt(p[2])
            if (!isNaN(r) && !isNaN(a)) { repo = r; aur = a }
            start = 2
        }
        // repo lines come first, then AUR; budget for the AUR tail so a long repo list cannot crowd it out
        const repoBudget = Math.max(0, root._maxDetail - Math.max(0, aur))
        const out = []
        let seen = 0, repoShown = 0
        let aurSection = root.manager === "aur"
        for (let i = start; i < lines.length && out.length < root._maxDetail; i++) {
            const line = lines[i].trim()
            if (line.length === 0) continue
            if (line === "DETAIL AUR") {
                aurSection = true
                continue
            }
            const parts = line.split(/\s+/)

            // checkupdates, paru and yay: name old -> new
            if (parts.length >= 4 && parts[2] === "->") {
                const isAur = aurSection || (repo >= 0 ? seen >= repo : root.manager === "aur")
                seen++
                if (!isAur) {
                    if (repoShown >= repoBudget) continue
                    repoShown++
                }
                root._detail(out, parts[0], parts[1], parts[3], isAur)
                continue
            }

            if (root.manager === "apt") {
                // name/suite new-version arch [upgradable from: old-version]
                const m = line.match(/^([^/\s]+)\/\S+\s+(\S+)\s+\S+(?:\s+\[upgradable from:\s+([^\]]+)\])?$/)
                if (m) root._detail(out, m[1], m[3] ?? "", m[2], false)
                continue
            }
            if (root.manager === "dnf") {
                // name.arch new-version repository
                if (parts.length !== 3 || parts[0].indexOf(".") < 1) continue
                const name = parts[0].replace(/\.(noarch|x86_64|aarch64|i[3-6]86|ppc64le|s390x|src)$/, "")
                root._detail(out, name, "", parts[1], false)
                continue
            }
            if (root.manager === "zypper") {
                // v | repository | name | installed | available | arch
                const cols = line.split("|").map(p => p.trim())
                if (cols.length >= 6 && cols[0] === "v")
                    root._detail(out, cols[2], cols[3], cols[4], false)
                continue
            }
            if (root.manager === "xbps") {
                // name-old_version update name-new_version
                const m = line.match(/^(.+)-([0-9][^\s]*_[0-9]+)\s+\S+\s+(.+)-([0-9][^\s]*_[0-9]+)$/)
                if (m) root._detail(out, m[1], m[2], m[4], false)
            }
        }
        root.repoCount = repo >= 0 ? repo : root.manager === "aur" ? 0 : root.count
        root.aurCount  = aur  >= 0 ? aur  : root.manager === "aur" ? root.count : 0
        root.packages  = out
    }

    function refresh(): void {
        // read the setting directly — on a manual toggle the `enabled` alias may not have re-evaluated yet
        if (!ShellSettings.updatesWidget || !supported || _proc.running) return
        // a manual check supersedes delayed recovery work. Leaving either timer armed makes a successful check run again a few seconds/minutes later
        _retry.stop()
        _reconnect.stop()
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
        root._failStreak = 0
    }

    function _sourcePreferenceChanged(): void {
        _retry.stop()
        _reconnect.stop()
        const wasRunning = _proc.running
        if (wasRunning) {
            root._discardResult = true
            _proc.running = false
        }
        if (!ShellSettings.updatesIncludeAur) {
            root.count = Math.max(0, root.repoCount)
            root.aurCount = 0
            root.packages = root.packages.filter(p => !p.aur)
        }
        if (!root.enabled) return
        root.ready = false
        if (!wasRunning) _sourceRefresh.restart()
    }

    BoundedProcess {
        id: _proc
        timeoutMs: 180000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _out }
        onTimeoutReached: {
            root.lastCheckMs = Date.now()
            root._touchNow()
            root.lastFailed = true
            root._failStreak++
            root.lastError = "Package check timed out"
            root.ready = true
            _retry.restart()
        }
        onExited: {
            if (_proc.timedOut) return
            if (root._discardResult) {
                root._discardResult = false
                _sourceRefresh.restart()
                return
            }
            root.lastCheckMs = Date.now()
            root._touchNow()
            if (!ShellSettings.updatesWidget) {
                root._resetDisabledState()
                return
            }
            const t = (_out.text || "").trim()
            const n = root._countFrom(t)
            if (!t.startsWith("ERR") && n >= 0) {
                root.count = n
                root._parseDetail(t)
                root.lastFailed = false
                root.lastError = ""
                root._failStreak = 0
                _retry.stop()
                _reconnect.stop()
            } else {
                root.lastFailed = true
                root._failStreak++
                root.lastError = t.startsWith("ERR")
                    ? root._safeError(t.substring(3).trim())
                    : "Package check returned an invalid count"
                _retry.restart()
            }
            root.ready = true
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
    Timer {
        id: _sourceRefresh
        interval: 0
        onTriggered: {
            root._discardResult = false
            if (root.supported) root.refresh()
            else root.ready = true
        }
    }
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
        function onUpdatesIncludeAurChanged() {
            root._sourcePreferenceChanged()
        }
    }
}
