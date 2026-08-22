pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string conflict: ""
    property bool   _checked: false
    property int    _generation: 0
    readonly property bool armed: SystemTools.hasBusctl

    function _check(): void {
        if (_checked || !SystemTools.ready || !SystemTools.hasBusctl) return
        _checked = true
        _delay.start()
    }

    function recheck(): void {
        root._generation++
        _delay.stop()
        if (_proc.running) _proc.running = false
        root._checked = false
        root.conflict = ""
        root._check()
    }

    Component.onCompleted: _check()
    Connections {
        target: SystemTools
        function onReadyChanged() { root._check() }
        function onScanRevisionChanged() { root.recheck() }
    }

    // settle delay: let our server and any autostarted daemon finish racing before we ask who won
    Timer {
        id: _delay
        interval: 5000
        repeat: false
        onTriggered: {
            _proc._generation = root._generation
            _proc.running = true
        }
    }

    BoundedProcess {
        id: _proc
        property int _generation: 0
        running: false
        timeoutMs: 5000
        // Ignore only this process. Another Quickshell instance can own the
        // notification name too, and is still a real conflict worth showing.
        command: ["bash", "-c",
            "self=$1; raw=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null); " +
            "set -- $raw; o=${2#\"}; o=${o%\"}; [ -n \"$o\" ] || exit 0; " +
            "raw=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s \"$o\" 2>/dev/null); " +
            "set -- $raw; p=$2; case $p in ''|*[!0-9]*) exit 0;; esac; " +
            "[ \"$p\" = \"$self\" ] && exit 0; " +
            "c=; IFS= read -r c < \"/proc/$p/comm\" 2>/dev/null || exit 0; " +
            "case \"$c\" in \"\") exit 0;; *) echo \"$c\";; esac",
            "bash", String(Quickshell.processId)]
        stdout: StdioCollector { id: _out }
        onExited: {
            if (_proc._generation !== root._generation) return
            const name = (_out.text || "").trim()
            root.conflict = name
            if (name.length === 0) return
            console.warn("silere-shell: notifications are owned by '" + name +
                "', not silere — its notification server is inactive. Stop the other daemon to use silere's notifications.")
        }
    }
}
