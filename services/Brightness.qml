pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int currentBrightness: 0
    property int maxBrightness:     0
    property string _device:        ""
    property var devices:           []
    property bool ready:            false
    readonly property bool toolAvailable:  SystemTools.hasBrightnessctl
    property bool _listed: false
    property bool _currentValid: false
    property bool _maxValid: false
    property int _reprobeAttempts: 0

    readonly property string deviceChoice: {
        const wanted = ShellSettings.brightnessDevice
        for (let i = 0; i < devices.length; i++)
            if (devices[i].name === wanted) return wanted
        return ""
    }
    readonly property var deviceChoices: {
        const out = [{ value: "", label: "Automatic" }]
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i]
            out.push({ value: d.name, label: d.name + (d.type.length > 0 ? " · " + d.type : "") })
        }
        return out
    }

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

    function setPercent(p: int): void {
        if (!toolAvailable || maxBrightness <= 0 || !_device) return
        const clamped = Math.max(1, Math.min(100, Math.round(p)))
        pendingPercent = clamped
        currentBrightness = Math.max(1, Math.round(maxBrightness * (clamped / 100)))
        _applyDebounce.restart()
    }

    function refresh(): void {
        if (!toolAvailable || !_device || _applyDebounce.running) return
        _brightnessFile.reload()
        _maxBrightnessFile.reload()
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
        _listProc.running = true
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._init() }
    }

    Connections {
        target: ShellSettings
        function onBrightnessDeviceChanged() { root._selectDevice() }
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open && root.toolAvailable && !root.ready) {
                root._reprobeAttempts = 0
                _reprobe.restart()
            }
        }
    }

    function _queueReprobe(): void {
        if (root._device.length === 0 || root._reprobeAttempts >= 3) return
        root._reprobeAttempts++
        _reprobe.restart()
    }

    function _syncReady(): void {
        root.ready = root._currentValid && root._maxValid
        if (root.ready) root._reprobeAttempts = 0
    }

    function _deviceScore(device): int {
        let score = device.type === "raw" ? 300 : device.type === "platform" ? 200 : 100
        const name = device.name.toLowerCase()
        if (/^(amdgpu_bl|intel_backlight|apple-panel|nvidia_wmi_ec_backlight)/.test(name)) score += 80
        else if (/^(nvidia|acpi_video)/.test(name)) score += 40
        else if (name.startsWith("ddcci")) score -= 180
        return score
    }

    function _selectDevice(): void {
        const wanted = ShellSettings.brightnessDevice
        let chosen = null
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i]
            if (wanted.length > 0 && d.name === wanted) { chosen = d; break }
            if (wanted.length === 0 && (!chosen || root._deviceScore(d) > root._deviceScore(chosen))) chosen = d
        }
        if (!chosen && devices.length > 0) {
            chosen = devices[0]
            for (let i = 1; i < devices.length; i++)
                if (root._deviceScore(devices[i]) > root._deviceScore(chosen)) chosen = devices[i]
        }

        const next = chosen ? chosen.name : ""
        if (root._device === next) {
            if (next.length > 0) root.refresh()
            return
        }
        root.ready = false
        root._currentValid = false
        root._maxValid = false
        root.currentBrightness = 0
        root.maxBrightness = 0
        root._device = next
        if (next.length > 0) root.refresh()
    }

    Process {
        id: _listProc
        command: ["bash", "-c",
            "for d in /sys/class/backlight/*; do " +
            "  [ -d \"$d\" ] || continue; " +
            "  n=${d##*/}; t=; m=; " +
            "  IFS= read -r t < \"$d/type\" 2>/dev/null || t=; " +
            "  IFS= read -r m < \"$d/max_brightness\" 2>/dev/null || m=; " +
            "  case $m in ''|*[!0-9]*) continue;; esac; " +
            "  [ \"$m\" -gt 0 ] && printf '%s\\t%s\\t%s\\n' \"$n\" \"$t\" \"$m\"; " +
            "done"]
        stdout: StdioCollector { id: _listOut }
        onExited: (code) => {
            if (code !== 0) { root.ready = false; root._listed = false; return }
            const lines = (_listOut.text || "").split(/\r?\n/)
            const devices = []
            for (let i = 0; i < lines.length; i++) {
                const p = lines[i].split("\t")
                const max = p.length >= 3 ? Number(p[2]) : 0
                if (p.length >= 3 && /^[A-Za-z0-9_.:+@-]+$/.test(p[0]) && isFinite(max) && max > 0)
                    devices.push({ name: p[0], type: p[1], max: max })
            }
            root.devices = devices
            root._selectDevice()
        }
    }

    Timer {
        id: _reprobe
        interval: 800
        onTriggered: {
            if (_listProc.running) { restart(); return }
            root._listed = false
            root._init()
        }
    }

    function _readValue(file): real {
        const value = parseInt((file.text() || "").trim())
        return !isNaN(value) && value >= 0 ? value : -1
    }

    FileView {
        id: _brightnessFile
        path: root._device.length > 0 ? "/sys/class/backlight/" + root._device + "/brightness" : ""
        watchChanges: root._device.length > 0
        printErrors: false
        onLoaded: {
            const value = root._readValue(_brightnessFile)
            root._currentValid = value >= 0
            if (root._currentValid) root.currentBrightness = value
            else root._queueReprobe()
            root._syncReady()
        }
        onLoadFailed: {
            root._currentValid = false
            root._syncReady()
            root._queueReprobe()
        }
        // gate like refresh(): a stale readback landing mid-debounce would clobber the optimistic value and drop queued scroll steps
        onFileChanged: if (!_applyDebounce.running) reload()
    }

    FileView {
        id: _maxBrightnessFile
        path: root._device.length > 0 ? "/sys/class/backlight/" + root._device + "/max_brightness" : ""
        watchChanges: root._device.length > 0
        printErrors: false
        onLoaded: {
            const value = root._readValue(_maxBrightnessFile)
            root._maxValid = value > 0
            if (root._maxValid) root.maxBrightness = value
            else root._queueReprobe()
            root._syncReady()
        }
        onLoadFailed: {
            root._maxValid = false
            root.maxBrightness = 0
            root._syncReady()
            root._queueReprobe()
        }
        onFileChanged: reload()
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
}
