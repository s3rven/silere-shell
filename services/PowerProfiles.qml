pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower as UPower

Singleton {
    id: root

    // the native service pushes reads; powerprofilesctl stays the write path so a
    // rejected change can report stderr
    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _set.running
    property string lastError: ""

    function profileName(value): string {
        switch (value) {
        case UPower.PowerProfile.PowerSaver:  return "power-saver"
        case UPower.PowerProfile.Balanced:    return "balanced"
        case UPower.PowerProfile.Performance: return "performance"
        default:                              return ""
        }
    }

    readonly property string profile: root.available
        ? root.profileName(UPower.PowerProfiles.profile) : ""
    readonly property bool performanceAvailable: root.available
        && UPower.PowerProfiles.hasPerformanceProfile

    function cycleOrder(serviceAvailable: bool, hasPerformance: bool): var {
        if (!serviceAvailable) return []
        return hasPerformance
            ? ["balanced", "performance", "power-saver"]
            : ["balanced", "power-saver"]
    }

    readonly property var _cycleOrder: root.cycleOrder(
        root.available, root.performanceAvailable)

    function degradationActive(profileName: string, reason): bool {
        return profileName === "performance"
            && (reason === UPower.PerformanceDegradationReason.LapDetected
                || reason === UPower.PerformanceDegradationReason.HighTemperature)
    }

    readonly property bool degraded: root.available && root.degradationActive(
        root.profile, UPower.PowerProfiles.degradationReason)

    readonly property string label: root.labelFor(root.profile)
    readonly property string glyph: root.glyphFor(root.profile)

    function labelFor(name: string): string {
        return name === "performance" ? "Performance"
             : name === "power-saver" ? "Power Saver"
             : name === "balanced"    ? "Balanced" : ""
    }
    function glyphFor(name: string): string {
        return name === "performance" ? "󰓅"
             : name === "power-saver" ? "󰾆" : "󰾅"
    }

    // least to most power, not the cycle order: a list is read top to bottom
    readonly property var choices: {
        if (!root.available) return []
        const names = root.performanceAvailable
            ? ["power-saver", "balanced", "performance"]
            : ["power-saver", "balanced"]
        return names.map(name => ({
            name: name,
            label: root.labelFor(name),
            glyph: root.glyphFor(name)
        }))
    }

    function setProfile(name: string): void {
        if (!root.available || _set.running) return
        const want = String(name)
        if (root._cycleOrder.indexOf(want) < 0 || want === root.profile) return
        root.lastError = ""
        _set.exec(["powerprofilesctl", "set", want])
    }

    function nextProfile(current: string, order: var): string {
        const at = order.indexOf(current)
        if (order.length < 2 || at < 0) return ""
        return order[(at + 1) % order.length]
    }

    // the daemon answers over dbus, so the caller is told what was asked for
    function cycle(): string {
        if (!root.available || root.profile.length === 0 || _set.running) return ""
        const next = root.nextProfile(root.profile, root._cycleOrder)
        if (next.length === 0) return ""
        root.setProfile(next)
        return next
    }

    onAvailableChanged: if (!root.available) {
        if (_set.running) _set.running = false
        root.lastError = ""
    }

    BoundedProcess {
        id: _set
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onTimeoutReached: root.lastError = "Power mode change timed out"
        onExited: (code) => {
            if (!root.available || timedOut) return
            root.lastError = code === 0 ? "" : SafeText.lastNonEmptyLine(
                _setErr.text, "Could not change the power mode", 160)
        }
    }
}
