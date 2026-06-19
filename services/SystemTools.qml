pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool ready: false
    property var _tools: ({})

    readonly property bool hasBrightnessctl: _tools.brightnessctl ?? false
    readonly property bool hasInotifywait:   _tools.inotifywait ?? false
    readonly property bool hasNmcli:         _tools.nmcli ?? false
    readonly property bool hasCava:          _tools.cava ?? false
    readonly property bool hasHyprsunset:    _tools.hyprsunset ?? false
    readonly property bool hasHyprlock:      _tools.hyprlock ?? false
    readonly property bool hasSystemctl:     _tools.systemctl ?? false
    readonly property bool hasHyprctl:       _tools.hyprctl ?? false
    readonly property bool hasPgrep:         _tools.pgrep ?? false
    readonly property bool hasPkill:         _tools.pkill ?? false
    readonly property bool hasNotifySend:    _tools["notify-send"] ?? false
    readonly property bool hasCavaConfig:    _tools["cava-config"] ?? false
    readonly property bool hasBusctl:        _tools.busctl ?? false
    readonly property bool hasCheckupdates:  _tools.checkupdates ?? false
    readonly property bool hasParu:          _tools.paru ?? false
    readonly property bool hasYay:           _tools.yay ?? false
    readonly property bool hasApt:           _tools.apt ?? false
    readonly property bool hasDnf:           _tools.dnf ?? false
    readonly property bool hasZypper:        _tools.zypper ?? false
    readonly property bool hasXbps:          _tools["xbps-install"] ?? false
    readonly property bool hasPowerProfilesCtl: _tools.powerprofilesctl ?? false
    readonly property bool hasMatugen:       _tools.matugen ?? false

    function refresh(): void {
        if (_checkProc.running) return
        ready = false
        _checkProc.exec(["bash", "-c",
            "for t in brightnessctl inotifywait nmcli cava hyprsunset hyprlock systemctl hyprctl pgrep pkill notify-send " +
            "busctl checkupdates paru yay apt dnf zypper xbps-install powerprofilesctl matugen; do " +
            "  command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; " +
            "done; " +
            "if [ -r \"$HOME/.config/cava/silere-shell.conf\" ]; then echo cava-config; fi"])
    }

    Component.onCompleted: refresh()

    Process {
        id: _checkProc
        stdout: StdioCollector { id: _checkOut }
        onExited: (code) => {
            if (code !== 0) { root.ready = true; return }
            const found = {}
            const lines = (_checkOut.text || "").split(/\r?\n/)
            for (let i = 0; i < lines.length; i++) {
                const name = lines[i].trim()
                if (name.length > 0) found[name] = true
            }
            root._tools = found
            root.ready = true
        }
    }
}
