pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

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
            "raw=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null); " +
            "set -- $raw; o=${2#\"}; o=${o%\"}; [ -n \"$o\" ] || exit 0; " +
            "raw=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s \"$o\" 2>/dev/null); " +
            "set -- $raw; p=$2; case $p in ''|*[!0-9]*) exit 0;; esac; " +
            "c=; IFS= read -r c < \"/proc/$p/comm\" 2>/dev/null || exit 0; " +
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
