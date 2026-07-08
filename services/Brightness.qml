pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property int currentBrightness: 0
    property int maxBrightness:     0
    property string _device:        ""
    property bool ready:            false
    readonly property bool toolAvailable:  SystemTools.hasBrightnessctl
    readonly property bool watchAvailable: SystemTools.hasInotifywait
    property bool _listed: false

    readonly property real   pct:   maxBrightness > 0 ? currentBrightness / maxBrightness : 0
    readonly property int    percent: Math.round(pct * 100)
    readonly property int    stepPct: 5
    readonly property string label:   `${percent}%`
    readonly property string icon: {
        if (pct <= 0)        return "󰃝"
        if (pct < 0.33)      return "󰃞"
        if (pct < 0.66)      return "󰃟"
        return "󰃠"
    }

    property int pendingPercent: percent
    onPercentChanged: pendingPercent = percent

    function bumpBy(delta: int): void {
        setPercent(pendingPercent + delta)
    }

    // Floored at 1% so the menu slider can't black the screen.
    function setPercent(p: int): void {
        if (!toolAvailable || maxBrightness <= 0 || !_device) return
        const clamped = Math.max(1, Math.min(100, Math.round(p)))
        pendingPercent = clamped
        currentBrightness = Math.max(1, Math.round(maxBrightness * (clamped / 100)))
        _applyDebounce.restart()
    }

    function refresh(): void {
        if (!toolAvailable || !_device || _applyDebounce.running || _infoProc.running) return
        _infoProc.exec(["brightnessctl", "-d", _device, "-m", "info"])
    }

    Component.onCompleted: _init()

    function _init(): void {
        if (_listed || !SystemTools.ready) return
        if (!toolAvailable) {
            ready = false
            maxBrightness = 0
            return
        }
        _listed = true
        _listProc.exec(["brightnessctl", "-l"])
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._init() }
    }

    Process {
        id: _listProc
        stdout: StdioCollector { id: _listOut }
        onExited: (code) => {
            if (code !== 0) { root.ready = false; root.maxBrightness = 0; root._listed = false; return }
            const lines = (_listOut.text || "").split(/\r?\n/)
            const prefs = ["amdgpu_bl2","amdgpu_bl1","amdgpu_bl0","intel_backlight","nvidia_0","nvidia_backlight"]
            let chosen = ""
            const devices = []
            for (let i = 0; i < lines.length; i++) {
                const m = lines[i].match(/Device '([^']+)' of class '([^']+)'/)
                if (m) devices.push({ name: m[1], cls: m[2] })
            }
            for (let i = 0; i < prefs.length && !chosen; i++)
                chosen = (devices.find(d => d.cls === "backlight" && d.name.startsWith(prefs[i])) || {}).name || ""
            // never fall back to an arbitrary LED — brightnessctl also lists keyboard LEDs, not displays
            if (!chosen) chosen = (devices.find(d => d.cls === "backlight") || {}).name || ""
            if (!chosen) {
                root.ready = false
                root.maxBrightness = 0
                root._listed = false
                return
            }
            // command before _device, or the watcher starts with a stale command
            if (root.watchAvailable) {
                // exec so bash is replaced by inotifywait -- otherwise killing
                // bash on reload orphans the inotifywait child (PPID 1 leak).
                _watchProc.command = [
                    "bash", "-c",
                    "exec inotifywait -m -q -e modify \"/sys/class/backlight/$1/brightness\"",
                    "brightness-watch", chosen
                ]
            }
            root._device = chosen
            root.refresh()
            if (!root.watchAvailable) _pollTimer.start()
        }
    }

    SupervisedProcess {
        id: _watchProc
        superviseWhen: root._device.length > 0 && root.watchAvailable
        cleanExitOnly: true
        stdout: SplitParser { onRead: root.refresh() }
    }

    Process {
        id: _infoProc
        stdout: StdioCollector { id: _infoOut }
        onExited: (code) => {
            if (code !== 0) return
            // format: name,class,current,current_pct%,max
            const parts = (_infoOut.text || "").trim().split(",")
            if (parts.length < 5) return
            const cur = parseInt(parts[2])
            const max = parseInt(parts[4])
            if (!isNaN(cur)) root.currentBrightness = cur
            if (!isNaN(max) && max > 0) root.maxBrightness = max
            root.ready = true
        }
    }

    Timer {
        id: _applyDebounce
        interval: 50
        onTriggered: {
            if (!root.toolAvailable || !root._device) return
            if (_setProc.running) { restart(); return }
            _setProc.exec(["brightnessctl", "-d", root._device, "set", `${root.pendingPercent}%`, "-q"])
        }
    }

    Process {
        id: _setProc
        onExited: Qt.callLater(root.refresh)
    }

    Timer {
        id: _pollTimer
        interval: 5000
        repeat: true
        running: false
        onTriggered: root.refresh()
    }
}
