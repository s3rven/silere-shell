import QtQuick
import "../../../config"

// one armed action per list: the first press arms a key ("forget:<ssid>"), a second within the window runs it
QtObject {
    id: root

    property int interval: 3000
    property string key: ""
    property real armedAtMs: 0

    // true when this press confirms the armed key; any other press arms it instead
    function press(k: string): bool {
        const now = Date.now()
        const age = now - root.armedAtMs
        if (root.key === k && age >= 0 && age < root.interval) {
            // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
            if (age < Metrics.confirmGuardMs) return false
            root.clear()
            return true
        }
        root.key = k
        root.armedAtMs = now
        _expiry.restart()
        return false
    }

    function clear(): void {
        root.key = ""
        _expiry.stop()
    }

    property Timer _expiry: Timer {
        interval: root.interval
        onTriggered: root.key = ""
    }
}
