import QtQuick
import Quickshell.Io

Process {
    id: root

    property int timeoutMs: 0
    property bool timedOut: false

    signal timeoutReached()

    property Connections _runningWatch: Connections {
        target: root
        function onRunningChanged() {
            if (root.running) root.timedOut = false
        }
    }

    property Timer _timeout: Timer {
        interval: Math.max(1, root.timeoutMs)
        running: root.running && root.timeoutMs > 0
        onTriggered: {
            if (!root.running) return
            root.timedOut = true
            root.running = false
            root.timeoutReached()
        }
    }
}
