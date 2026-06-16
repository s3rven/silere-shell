pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    readonly property bool isIdle: _monitor.isIdle

    IdleMonitor {
        id: _monitor
        timeout: 600              // seconds — aligned with hypridle dpms-off
        respectInhibitors: true
    }
}
