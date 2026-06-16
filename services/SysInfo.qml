pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real memTotalKb: 0
    property real memAvailKb: 0
    property real uptimeSecs: 0
    property real diskUsedKb: 0
    property real diskTotalKb: 0
    property int  processCount: 0
    property real cpuPct: 0
    property real _lastCpuTotal: 0
    property real _lastCpuIdle: 0

    readonly property real memUsedGb:  (memTotalKb - memAvailKb) / (1024 * 1024)
    readonly property real memTotalGb: memTotalKb / (1024 * 1024)
    readonly property real memPct:     memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0
    readonly property real diskPct:    diskTotalKb > 0 ? diskUsedKb / diskTotalKb : 0

    readonly property string memLabel: {
        if (memTotalKb <= 0) return "—"
        return memUsedGb.toFixed(1) + " / " + Math.round(memTotalGb) + "G"
    }

    readonly property string diskLabel: {
        if (diskTotalKb <= 0) return "—"
        const used  = (diskUsedKb  / 1048576).toFixed(0)
        const total = (diskTotalKb / 1048576).toFixed(0)
        return used + " / " + total + " GB"
    }

    readonly property string uptimeLabel: {
        if (uptimeSecs <= 0) return "—"
        const s = Math.floor(uptimeSecs)
        if (s < 60) return s + "s"                       // fresh boot — show seconds, not "0m"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + h + "h " + m + "m"   // keep minutes past a day
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    // Exact wall-clock boot time, derived from uptime. Revealed on hover in the
    // menu's system card. Minute precision, so it doesn't jitter between polls.
    readonly property string bootTimeLabel: {
        if (uptimeSecs <= 0) return ""
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        const dt = new Date(Date.now() - uptimeSecs * 1000)
        const hh = ("0" + dt.getHours()).slice(-2)
        const mm = ("0" + dt.getMinutes()).slice(-2)
        return "up since " + days[dt.getDay()] + " " + hh + ":" + mm
    }

    // The system stats are only shown on the menu's "Now" page, so the polling
    // runs only while the menu is open. Last values persist between opens, so
    // reopening shows them instantly and they refresh within one tick.
    property bool _active: false

    function _activate(): void {
        if (_active) return
        _active = true
        _refreshFast()
        _refreshSlow()
    }

    function _deactivate(): void {
        _startDelay.stop()
        _poll.stop()
        _slowPoll.stop()
        _active = false
        _lastCpuTotal = 0
        _lastCpuIdle = 0
        if (_slowProc.running) _slowProc.running = false
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open) _startDelay.restart()
            else root._deactivate()
        }
    }

    // Created lazily on first open, after open already flipped true, catch that missed edge.
    Component.onCompleted: if (MenuState.open) _startDelay.restart()

    // Small delay so the loop isn't spawned during the open animation.
    Timer { id: _startDelay; interval: 120; onTriggered: root._activate() }

    Timer {
        id: _poll
        interval: 2000
        repeat: true
        running: root._active
        onTriggered: root._refreshFast()
    }

    Timer {
        id: _slowPoll
        interval: 10000
        repeat: true
        running: root._active
        onTriggered: root._refreshSlow()
    }

    FileView {
        id: _meminfoFile
        path: "/proc/meminfo"
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: _uptimeFile
        path: "/proc/uptime"
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: _statFile
        path: "/proc/stat"
        blockLoading: true
        blockAllReads: true
        printErrors: false
    }

    function _readFile(view): string {
        try {
            view.reload()
            view.waitForJob()
            return view.text()
        } catch (e) {
            return ""
        }
    }

    property bool _fastRefreshing: false

    function _refreshFast(): void {
        if (_fastRefreshing || !_active) return
        _fastRefreshing = true
        try {

        const mem = _readFile(_meminfoFile)
        const total = mem.match(/^MemTotal:\s+(\d+)/m)
        const avail = mem.match(/^MemAvailable:\s+(\d+)/m)
        if (total && avail) {
            root.memTotalKb = parseInt(total[1]) || 0
            root.memAvailKb = parseInt(avail[1]) || 0
        }

        const up = _readFile(_uptimeFile).trim().split(/\s+/)
        if (up.length > 0) root.uptimeSecs = parseFloat(up[0]) || 0

        const _cpuRaw = _readFile(_statFile)
        const _cpuNl  = _cpuRaw.indexOf('\n')
        const cpuLine = _cpuNl < 0 ? _cpuRaw.trim() : _cpuRaw.slice(0, _cpuNl)
        const p = cpuLine.trim().split(/\s+/)
        if (p.length >= 9 && p[0] === "cpu") {
            const vals = []
            for (let i = 1; i <= 8; i++) vals.push(parseInt(p[i]) || 0)
            const idle  = vals[3] + vals[4]
            const total = vals.reduce((s, v) => s + v, 0)
            if (root._lastCpuTotal > 0 && total > root._lastCpuTotal) {
                const dTotal = total - root._lastCpuTotal
                const dIdle  = idle  - root._lastCpuIdle
                root.cpuPct = Math.max(0, Math.min(1, (dTotal - dIdle) / dTotal))
            }
            root._lastCpuTotal = total
            root._lastCpuIdle  = idle
        }

        } finally {
            root._fastRefreshing = false
        }
    }

    function _refreshSlow(): void {
        if (_slowProc.running) return
        _slowProc.exec(["bash", "-c",
            "set -- /proc/[0-9]*; printf 'p%s\\n' \"$#\"; " +
            "df -k / 2>/dev/null | { " +
            "  read -r _; " +
            "  read -r _ total used _; " +
            "  [ -n \"$total\" ] && printf 'd%s %s\\n' \"$used\" \"$total\"; " +
            "}"])
    }

    Process {
        id: _slowProc
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("p")) {
                    root.processCount = parseInt(line.slice(1)) || 0
                } else if (line.startsWith("d")) {
                    const p = line.slice(1).trim().split(/\s+/)
                    if (p.length >= 2) {
                        root.diskUsedKb  = parseInt(p[0]) || 0
                        root.diskTotalKb = parseInt(p[1]) || 0
                    }
                }
            }
        }
        Component.onDestruction: running = false
    }
}
