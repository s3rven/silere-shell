pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool ready: false
    property bool checking: false
    property string lastError: ""
    property var _tools: ({})
    property string packageFamily: ""
    // ready stays true during a refresh so controls do not disappear. Consumers
    // that need to redo work after a coherent scan use this completion edge.
    property int _scanRevision: 0
    readonly property int scanRevision: _scanRevision

    readonly property bool probeFailed: ready && lastError.length > 0

    readonly property bool hasBrightnessctl: _tools.brightnessctl ?? false
    readonly property bool hasInotifywait:   _tools.inotifywait ?? false
    readonly property bool hasNmcli:         _tools.nmcli ?? false
    readonly property bool hasCava:          _tools.cava ?? false
    readonly property bool hasMatugen:       _tools.matugen ?? false
    readonly property bool hasHyprsunset:    _tools.hyprsunset ?? false
    readonly property bool hasWlsunset:      _tools.wlsunset ?? false
    readonly property bool hasHyprlock:      _tools.hyprlock ?? false
    readonly property bool hasSwaylock:      _tools.swaylock ?? false
    readonly property bool hasGtklock:       _tools.gtklock ?? false
    readonly property bool hasSystemctl:     _tools.systemctl ?? false
    readonly property bool hasLoginctl:      _tools.loginctl ?? false
    readonly property bool hasHyprctl:       _tools.hyprctl ?? false
    readonly property bool hasPgrep:         _tools.pgrep ?? false
    readonly property bool hasPkill:         _tools.pkill ?? false
    readonly property bool hasNotifySend:    _tools["notify-send"] ?? false
    readonly property bool hasBusctl:        _tools.busctl ?? false
    readonly property bool hasCheckupdates:  _tools.checkupdates ?? false
    readonly property bool hasParu:          _tools.paru ?? false
    readonly property bool hasYay:           _tools.yay ?? false
    readonly property bool hasTimeout:       _tools.timeout ?? false
    readonly property bool hasApt:           _tools.apt ?? false
    readonly property bool hasDnf:           _tools.dnf ?? false
    readonly property bool hasZypper:        _tools.zypper ?? false
    readonly property bool hasXbps:          _tools["xbps-install"] ?? false
    readonly property bool hasPowerProfilesCtl: _tools.powerprofilesctl ?? false
    readonly property bool hasPowerProfilesService: _tools["@powerprofiles"] ?? false
    readonly property bool hasFcList:        _tools["fc-list"] ?? false
    readonly property bool hasPwvucontrol:   _tools.pwvucontrol ?? false
    readonly property bool hasPavucontrol:   _tools.pavucontrol ?? false

    // "" | working | done | failed
    property string matugenRepairState: ""

    function _repairOutcome(code: int, timedOut: bool): string {
        return !timedOut && code === 0 ? "done" : "failed"
    }

    // the repair outlives the settings section that starts it; a page unload must not orphan the process or drop its result
    function repairMatugen(): void {
        if (root.matugenRepairState === "working") return
        root.matugenRepairState = "working"
        _matugenRepair.running = true
    }

    BoundedProcess {
        id: _matugenRepair
        timeoutMs: 15000
        command: ["bash", Quickshell.shellDir + "/scripts/install.sh", "--repair-matugen"]
        // a killed process still emits exited, sometimes with a successful-looking status
        onExited: code => root.matugenRepairState = root._repairOutcome(
            code, _matugenRepair.timedOut)
        onTimeoutReached: root.matugenRepairState = "failed"
        Component.onDestruction: running = false
    }

    function _shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // the power commands are already derived from these flags; this is the guard for a tool that went away between derivation and the click
    function commandAvailable(command): bool {
        if (!command || command.length === 0) return false
        const tool = String(command[0])
        if (tool === "hyprlock")  return root.hasHyprlock
        if (tool === "swaylock")  return root.hasSwaylock
        if (tool === "gtklock")   return root.hasGtklock
        if (tool === "systemctl") return root.hasSystemctl
        if (tool === "loginctl")  return root.hasLoginctl
        if (tool === "hyprsunset") return root.hasHyprsunset
        if (tool === "wlsunset")   return root.hasWlsunset
        if (tool === "pwvucontrol") return root.hasPwvucontrol
        if (tool === "pavucontrol") return root.hasPavucontrol
        return true
    }

    function runOrNotify(command, failTitle: string): void {
        if (!command || command.length === 0) return
        if (!root.hasNotifySend) {
            Quickshell.execDetached(command)
            return
        }
        const note = "notify-send --urgency=critical --app-name=silere-shell " +
            root._shq(failTitle) + " " + root._shq("It may require authorization or be blocked by a running task.")
        const argv = ["bash", "-c", '"$@" || ' + note, "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        Quickshell.execDetached(argv)
    }

    readonly property int _minRetryDelayMs: 5000
    readonly property int _maxRetryDelayMs: 120000
    property int _retryDelayMs: 0
    property real _lastScanMs: 0

    // the scan itself failing to land says nothing about whether a tool was
    // actually removed; wiping _tools here would tear down NightLight, cava
    // and Updates over a transient hiccup, so keep the last-known set and
    // retry with backoff instead of advertising a false negative
    function _scanFailed(message: string): void {
        root.lastError = message
        root.ready = true
        root.checking = false
        root._lastScanMs = Date.now()
        root._scanRevision++
        root._retryDelayMs = root._retryDelayMs > 0
            ? Math.min(root._retryDelayMs * 2, root._maxRetryDelayMs)
            : root._minRetryDelayMs
        _retryTimer.restart()
    }

    Timer {
        id: _retryTimer
        interval: root._retryDelayMs
        onTriggered: root.refresh()
    }

    // opening a section re-runs the full probe; only do that when the last answer
    // is stale, while the Refresh control still forces one
    function refreshIfStale(maxAgeMs: int): void {
        if (root._lastScanMs > 0 && Date.now() - root._lastScanMs < maxAgeMs) return
        root.refresh()
    }

    function refresh(): void {
        if (_checkProc.running) return
        // keep the last confirmed capability set while refreshing. Features no longer disappear briefly when Settings triggers a fresh probe
        checking = true
        lastError = ""
        _checkProc.exec(["bash", "-c",
            "family=; if [ -r /etc/os-release ]; then " +
            "  . /etc/os-release; for id in ${ID:-} ${ID_LIKE:-}; do " +
            "    case $id in " +
            "      arch|manjaro|endeavouros|garuda) family=pacman ;; " +
            "      debian|ubuntu|linuxmint|pop) family=apt ;; " +
            "      fedora|rhel|centos|rocky|almalinux) family=dnf ;; " +
            "      opensuse*|suse|sles) family=zypper ;; " +
            "      void) family=xbps ;; " +
            "    esac; [ -n \"$family\" ] && break; " +
            "  done; " +
            "fi; [ -n \"$family\" ] && echo \"@family=$family\"; " +
            // tuned-ppd serves the same bus API without shipping powerprofilesctl
            "command -v busctl >/dev/null 2>&1 && busctl --system --no-pager --timeout=2 get-property " +
            "net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile " +
            ">/dev/null 2>&1 && echo @powerprofiles; " +
            "for t in brightnessctl inotifywait nmcli cava matugen hyprsunset wlsunset hyprlock swaylock gtklock systemctl loginctl hyprctl pgrep pkill notify-send " +
            "busctl checkupdates paru yay timeout apt dnf zypper xbps-install powerprofilesctl fc-list pwvucontrol pavucontrol; do " +
            "  command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; " +
            // the last lookup is optional; do not inherit its `command -v` status and discard every tool found before it
            "done; exit 0"])
    }

    Component.onCompleted: refresh()

    BoundedProcess {
        id: _checkProc
        timeoutMs: 15000
        stdout: StdioCollector { id: _checkOut }
        onTimeoutReached: root._scanFailed("Optional tool scan timed out")
        onExited: (code) => {
            if (_checkProc.timedOut) return
            if (code !== 0) {
                root._scanFailed("Optional tool scan failed (exit " + code + ")")
                return
            }
            root._retryDelayMs = 0
            const found = {}
            let family = ""
            const lines = (_checkOut.text || "").split(/\r?\n/)
            for (let i = 0; i < lines.length; i++) {
                const name = lines[i].trim()
                if (name.startsWith("@family=")) family = name.slice(8)
                else if (name.length > 0) found[name] = true
            }
            root._tools = found
            root.packageFamily = family
            root.lastError = ""
            root.ready = true
            root.checking = false
            root._lastScanMs = Date.now()
            root._scanRevision++
        }
    }
}
