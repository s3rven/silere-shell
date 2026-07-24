pragma Singleton

import QtQuick
import Quickshell

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

    Timer { id: _settle; interval: 80; onTriggered: root._hyprActive = root._raw }
}
