pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// tracks the scrolloverview plugin's overview. the local plugin patch emits socket2
// scrolloverview>>1 on open, >>0 when the close animation finishes, so the bar can get out of the way
Singleton {
    id: root

    property bool active: false
    property bool _raw: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "scrolloverview") return
            root._raw = event.data === "1"
            _settle.restart()
        }
    }

    // settle delay collapses rapid open/close flapping into one state change so the bar never stutters
    Timer { id: _settle; interval: 80; onTriggered: root.active = root._raw }
}
