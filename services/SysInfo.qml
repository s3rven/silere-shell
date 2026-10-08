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
    property real diskAvailKb: 0
    property real _lastDiskReadMs: 0
    readonly property int _diskRefreshMs: 60000
    property real cpuPct: 0
    property bool cpuReady: false
    property real _lastCpuTotal: 0
    property real _lastCpuIdle: 0

    readonly property real memPct:     memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0
    // as df counts it: blocks reserved for root are neither used nor available to the user
    readonly property real diskPct:    diskUsedKb + diskAvailKb > 0 ? diskUsedKb / (diskUsedKb + diskAvailKb) : 0

    readonly property string uptimeLabel: {
        if (uptimeSecs <= 0) return "—"
        const s = Math.floor(uptimeSecs)
        if (s < 60) return s + "s"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    property bool _active: false
    readonly property bool _wanted: MenuState.homeActive && !Idle.isIdle

    on_WantedChanged: {
        if (_wanted) _startDelay.restart()
        else root._deactivate()
    }

    function _activate(): void {
        if (_active) return
        _active = true
        cpuReady = false
        _refreshFast()
        _uptimeFile.reload()
        _refreshSlow()
        // cpuPct is a delta between two /proc/stat reads; without a quick second sample the tile shows the last session's figure
        _cpuPrime.restart()
    }

    function _deactivate(): void {
        _startDelay.stop()
        _cpuPrime.stop()
        _uptimePoll.stop()
        _active = false
        cpuReady = false
        _lastCpuTotal = 0
        _lastCpuIdle = 0
        if (_slowProc.running) _slowProc.running = false
    }

    // created lazily on first open, after open already flipped true, catch that missed edge
    Component.onCompleted: if (_wanted) _startDelay.restart()

    Timer { id: _startDelay; interval: 120; onTriggered: root._activate() }
    Timer { id: _cpuPrime; interval: 250; onTriggered: if (root._active) _statFile.reload() }
    Timer { id: _uptimePoll; onTriggered: if (root._active) _uptimeFile.reload() }

    Timer {
        id: _poll
        interval: 2000
        repeat: true
        running: root._active
        onTriggered: root._refreshFast()
    }

    Timer {
        id: _slowPoll
        interval: root._diskRefreshMs
        repeat: true
        running: root._active
        onTriggered: root._refreshSlow()
    }

    FileView {
        id: _meminfoFile
        path: "/proc/meminfo"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyMeminfo(_meminfoFile.text())
        onLoadFailed: if (root._active) { root.memTotalKb = 0; root.memAvailKb = 0 }
    }

    FileView {
        id: _uptimeFile
        path: "/proc/uptime"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyUptime(_uptimeFile.text())
        onLoadFailed: {
            if (!root._active) return
            _uptimePoll.interval = 2000
            _uptimePoll.restart()
        }
    }

    FileView {
        id: _statFile
        path: "/proc/stat"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyCpuStat(_statFile.text())
        onLoadFailed: if (root._active) root._clearCpuSample()
    }

    function _refreshFast(): void {
        if (!_active) return
        _meminfoFile.reload()
        _statFile.reload()
    }

    function _applyMeminfo(mem: string): void {
        if (!root._active) return
        const total = mem.match(/^MemTotal:\s+(\d+)/m)
        const avail = mem.match(/^MemAvailable:\s+(\d+)/m)
        const totalKb = total ? Number(total[1]) : 0
        const availKb = avail ? Number(avail[1]) : NaN
        root.memTotalKb = isFinite(totalKb) && totalKb > 0 && isFinite(availKb) ? totalKb : 0
        root.memAvailKb = root.memTotalKb > 0
            ? Math.max(0, Math.min(root.memTotalKb, availKb)) : 0
    }

    function _applyUptime(raw: string): void {
        if (!root._active) return
        const up = raw.trim().split(/\s+/)
        root.uptimeSecs = parseFloat(up[0]) || 0
        _uptimePoll.interval = root.uptimeSecs < 60 ? 2000
            : Math.max(1000, Math.ceil((60 - root.uptimeSecs % 60) * 1000) + 100)
        _uptimePoll.restart()
    }

    function _clearCpuSample(): void {
        root.cpuReady = false
        root.cpuPct = 0
        root._lastCpuTotal = 0
        root._lastCpuIdle = 0
    }

    function _applyCpuStat(_cpuRaw: string): void {
        if (!root._active) return
        const _cpuNl  = _cpuRaw.indexOf('\n')
        const cpuLine = _cpuNl < 0 ? _cpuRaw.trim() : _cpuRaw.slice(0, _cpuNl)
        const p = cpuLine.trim().split(/\s+/)
        if (p.length >= 9 && p[0] === "cpu") {
            const vals = []
            for (let i = 1; i <= 8; i++) {
                const value = Number(p[i])
                if (!/^[0-9]+$/.test(p[i]) || !isFinite(value)) {
                    root._clearCpuSample()
                    return
                }
                vals.push(value)
            }
            const idle  = vals[3] + vals[4]
            const total = vals.reduce((s, v) => s + v, 0)
            if (!isFinite(total) || !isFinite(idle)) {
                root._clearCpuSample()
                return
            }
            if (root._lastCpuTotal > 0 && total > root._lastCpuTotal) {
                const dTotal = total - root._lastCpuTotal
                const dIdle  = idle  - root._lastCpuIdle
                // hotplug and counter resets move the totals backwards; re-prime instead of keeping a stale or 100% reading
                root.cpuReady = dIdle >= 0 && dIdle <= dTotal
                root.cpuPct = root.cpuReady ? (dTotal - dIdle) / dTotal : 0
            } else {
                root.cpuReady = false
                root.cpuPct = 0
            }
            root._lastCpuTotal = total
            root._lastCpuIdle  = idle
        } else {
            root._clearCpuSample()
        }
    }

    function _refreshSlow(): void {
        if (_slowProc.running) return
        const elapsed = Date.now() - root._lastDiskReadMs
        if (root._lastDiskReadMs > 0 && elapsed >= 0 && elapsed < root._diskRefreshMs) {
            _slowPoll.interval = Math.max(1000, root._diskRefreshMs - elapsed)
            _slowPoll.restart()
            return
        }
        _slowPoll.interval = root._diskRefreshMs
        _slowProc.exec(["df", "-Pk", "/"])
    }

    function _applyDiskStat(raw: string): bool {
        if (!root._active) return false
        // -P keeps the device on one line. Read from the right to allow spaces in it.
        const lines = raw.trim().split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].trim().split(/\s+/)
            const n = fields.length
            if (n < 6 || fields[n - 1] !== "/") continue
            const values = fields.slice(n - 5, n - 2)
            if (!values.every(value => /^[0-9]+$/.test(value) && isFinite(Number(value)))) continue
            root.diskTotalKb = Number(values[0])
            root.diskUsedKb = Number(values[1])
            root.diskAvailKb = Number(values[2])
            root._lastDiskReadMs = Date.now()
            _slowPoll.interval = root._diskRefreshMs
            _slowPoll.restart()
            return true
        }
        return false
    }

    BoundedProcess {
        id: _slowProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _diskOut }
        onExited: code => {
            if (code === 0 && !_slowProc.timedOut) root._applyDiskStat(_diskOut.text)
        }
        Component.onDestruction: running = false
    }
}
