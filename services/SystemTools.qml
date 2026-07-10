pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool ready: false
    property var _tools: ({})
    property string packageFamily: ""

    readonly property bool hasBrightnessctl: _tools.brightnessctl ?? false
    readonly property bool hasInotifywait:   _tools.inotifywait ?? false
    readonly property bool hasNmcli:         _tools.nmcli ?? false
    readonly property bool hasCava:          _tools.cava ?? false
    readonly property bool hasHyprsunset:    _tools.hyprsunset ?? false
    readonly property bool hasHyprlock:      _tools.hyprlock ?? false
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
    readonly property bool hasMatugen:       _tools.matugen ?? false
    readonly property bool hasFcList:        _tools["fc-list"] ?? false

    function refresh(): void {
        if (_checkProc.running) return
        ready = false
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
            "for t in brightnessctl inotifywait nmcli cava hyprsunset hyprlock systemctl loginctl hyprctl pgrep pkill notify-send " +
            "busctl checkupdates paru yay timeout apt dnf zypper xbps-install powerprofilesctl matugen fc-list; do " +
            "  command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; " +
            "done"])
    }

    Component.onCompleted: refresh()

    Process {
        id: _checkProc
        stdout: StdioCollector { id: _checkOut }
        onExited: (code) => {
            if (code !== 0) { root.ready = true; return }
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
            root.ready = true
        }
    }
}
