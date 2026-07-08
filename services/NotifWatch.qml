pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// one-shot startup diagnostic: if another daemon (mako/dunst/swaync) owns org.freedesktop.Notifications,
// silere's server is queued and sees nothing. surfaces the culprit; OsdBarState watches `conflict` to flash a warning
Singleton {
    id: root

    // Non-empty = a rival daemon owns the bus name; holds its process name.
    property string conflict: ""
    property bool   _checked: false
    readonly property bool armed: SystemTools.hasBusctl

    function _check(): void {
        if (_checked || !SystemTools.ready || !SystemTools.hasBusctl) return
        _checked = true
        _delay.start()
    }

    Component.onCompleted: _check()
    Connections {
        target: SystemTools
        function onReadyChanged() { root._check() }
    }

    // settle delay: let our server and any autostarted daemon finish racing before we ask who won
    Timer {
        id: _delay
        interval: 5000
        repeat: false
        onTriggered: _proc.running = true
    }

    Process {
        id: _proc
        running: false
        command: ["bash", "-c",
            "o=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null | tr -d '\"' | awk 'NR==1{print $2}'); " +
            "[ -z \"$o\" ] && exit 0; " +
            "p=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s \"$o\" 2>/dev/null | awk 'NR==1{print $2}'); " +
            "[ -z \"$p\" ] && exit 0; " +
            "c=$(cat /proc/$p/comm 2>/dev/null); " +
            "case \"$c\" in *quickshell*|qs) exit 0;; \"\") exit 0;; *) echo \"$c\";; esac"]
        stdout: StdioCollector { id: _out }
        onExited: {
            const name = (_out.text || "").trim()
            if (name.length === 0) return
            root.conflict = name
            console.warn("silere-shell: notifications are owned by '" + name +
                "', not silere — its notification server is inactive. Stop the other daemon to use silere's notifications.")
        }
    }
}
