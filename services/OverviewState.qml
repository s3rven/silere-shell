pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Tracks the scrolloverview plugin's workspace overview. The event is emitted
// by the local plugin patch (socket2: scrolloverview>>1 on open, >>0 once the
// close animation finishes), so the bar can get out of the way while the
// workspaces are zoomed out.
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

    // Settle delay collapses rapid open/close flapping (scripted toggles,
    // cancelled swipes) into one state change so the bar never stutters.
    Timer { id: _settle; interval: 80; onTriggered: root.active = root._raw }
}
