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
        // two units at most — the third adds noise, not information
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    // system stats only show on the Now page, so poll only while that tab's visible
    property bool _active: false
    readonly property bool _wanted: MenuState.open && MenuState.activeTab === 0 && !Idle.isIdle

    on_WantedChanged: {
        if (_wanted) _startDelay.restart()
        else root._deactivate()
    }

    function _activate(): void {
        if (_active) return
        _active = true
        _refreshFast()
        _refreshSlow()
    }

    function _deactivate(): void {
        _startDelay.stop()
        _active = false
        _lastCpuTotal = 0
        _lastCpuIdle = 0
        if (_slowProc.running) _slowProc.running = false
    }

    // Created lazily on first open, after open already flipped true, catch that missed edge.
    Component.onCompleted: if (_wanted) _startDelay.restart()

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

    function _readView(view): string {
        try {
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

        _meminfoFile.reload()
        _uptimeFile.reload()
        _statFile.reload()

        const mem = _readView(_meminfoFile)
        const total = mem.match(/^MemTotal:\s+(\d+)/m)
        const avail = mem.match(/^MemAvailable:\s+(\d+)/m)
        if (total && avail) {
            root.memTotalKb = parseInt(total[1]) || 0
            root.memAvailKb = parseInt(avail[1]) || 0
        }

        const up = _readView(_uptimeFile).trim().split(/\s+/)
        if (up.length > 0) root.uptimeSecs = parseFloat(up[0]) || 0

        const _cpuRaw = _readView(_statFile)
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
                if (!root._active) return
                if (line.startsWith("d")) {
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
