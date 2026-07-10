pragma Singleton

import QtQuick
import Quickshell

// backend-neutral overview state. niri emits it natively via Compositor's event
// stream; on Hyprland the scrolloverview plugin patch sends socket2 scrolloverview>>1
// on open, >>0 when the close animation finishes, so the bar can get out of the way.
Singleton {
    id: root

    readonly property bool active: Compositor.isNiri ? Compositor.overviewActive : _hyprActive

    property bool _hyprActive: false
    property bool _raw: false

    Connections {
        target: Compositor
        enabled: Compositor.isHyprland
        function onOverviewRaw(open) {
            root._raw = open
            _settle.restart()
        }
    }

    // settle delay collapses rapid open/close flapping into one state change so the bar never stutters
    Timer { id: _settle; interval: 80; onTriggered: root._hyprActive = root._raw }
}
