pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    readonly property bool isIdle: _monitor.isIdle

    // a lock screen typically covers the session well before the blank stage below, and the
    // simple animation driver paces by wall time, so nothing stops on its own behind it
    readonly property bool isQuiet: _quiet.isIdle || _monitor.isIdle

    IdleMonitor {
        id: _quiet
        // seconds — unbounded per-frame work only; surfaces stay put. Sits on the usual dim
        // stage, since audio alone holds no inhibitor and a freeze on a lit screen is visible
        timeout: 240
        respectInhibitors: true
    }

    IdleMonitor {
        id: _monitor
        timeout: 600              // seconds — aligned with hypridle's screen-blank stage
        respectInhibitors: true
    }

    // session only: a restart or a crash must never leave the screen awake; shell.qml holds the inhibitor
    property bool keepAwake: false
    function toggleKeepAwake(): void { root.keepAwake = !root.keepAwake }
}
