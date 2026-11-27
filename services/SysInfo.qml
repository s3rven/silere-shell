pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property real memTotalKb: 0
    property real memAvailKb: 0
    property real swapTotalKb: 0
    property real swapUsedKb: 0
    // percent of the last 10 s that some task spent stalled on memory, from the kernel's own pressure counter
    property real memPressure: 0
    // enters on a real stall and leaves only once it has eased, so a reading near the line never flickers
    property bool _memStalled: false
    // used swap alone is not news: zram with a high swappiness fills it on a healthy machine, and
    // pages stay there long after a squeeze ends, so the figure needs a stall to be worth showing
    readonly property bool swapActive: _memStalled && swapTotalKb > 0 && swapUsedKb >= 65536
    property real uptimeSecs: 0
    property real diskUsedKb: 0
    property real diskTotalKb: 0
    property real diskAvailKb: 0
    property real _lastDiskReadMs: 0
    readonly property int _diskRefreshMs: 60000
    property real cpuPct: 0
    property bool cpuReady: false
    property bool cpuHigh: false
    property int _cpuBusySamples: 0
    property real _lastCpuTotal: 0
    property real _lastCpuIdle: 0

    readonly property RequestSet _topRequests: RequestSet {}
    function requestTopProcess(owner, wanted: bool): void {
        root._topRequests.set(owner, wanted)
    }
    readonly property bool _topWanted: root._active && root._topRequests.active
    property string topName: ""
    property int topPid: 0
    property bool topShown: false
    property int _topSamples: 0
    property var _topLast: null
    on_TopWantedChanged: {
        if (root._topWanted) {
            root._topRelease.stop()
            root._startTop()
        } else root._topRelease.restart()
    }
    // the table costs a spawn and a ~100 KB parse (30 ms cold): read only while a name could show
    property int _cpuCount: 1
    readonly property bool _topPossible: root.topPossible(root.cpuReady, root.cpuPct, root._cpuCount)
    on_TopPossibleChanged: {
        if (!root._topWanted) return
        if (root._topPossible) root._startTop()
        else root._clearTop()
    }

    readonly property real memPct:     memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0
    // as df counts it: blocks reserved for root are neither used nor available to the user
    readonly property real diskPct:    diskUsedKb + diskAvailKb > 0 ? diskUsedKb / (diskUsedKb + diskAvailKb) : 0

    // 0 calm, 1 above 75%, 2 above 90%; each band lets go three points under its line, so a reading
    // that sits on one holds its tint instead of blinking it on every poll. Shared so the bar and Home agree
    function usageLevel(pct: real, was: int): int {
        const enter = pct > 0.9 ? 2 : pct > 0.75 ? 1 : 0
        return Math.max(enter, Math.min(was, pct > 0.87 ? 2 : pct > 0.72 ? 1 : 0))
    }
    property int memLevel: 0
    property int diskLevel: 0
    onMemPctChanged: memLevel = usageLevel(memPct, memLevel)
    onDiskPctChanged: diskLevel = usageLevel(diskPct, diskLevel)

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
    readonly property bool _homeWanted: MenuState.homeActive && !Idle.isIdle
    readonly property bool monitorHasReadings: ShellSettings.systemShowCpu || ShellSettings.systemShowMemory
        || (ShellSettings.systemShowTemp && !CpuTemp.sensorMissing)
    // the bar's monitor reads only /proc; disk and uptime stay with Home, so the bar never spawns df
    // Motion.unseen: a fullscreen window covers the only bar, and a game's input keeps the session from idling for hours
    readonly property bool _barWanted: ShellSettings.barShowSystem
        && (ShellSettings.systemShowCpu || ShellSettings.systemShowMemory)
        && !Idle.isIdle && !OverviewState.active && !Motion.unseen
    readonly property bool _wanted: _homeWanted || _barWanted
    readonly property bool _cpuWanted: _homeWanted || (_barWanted && ShellSettings.systemShowCpu)
    readonly property bool _memoryWanted: _homeWanted || (_barWanted && ShellSettings.systemShowMemory)

    on_WantedChanged: {
        if (_wanted) {
            root._releaseHold.stop()
            _startDelay.restart()
        } else {
            _startDelay.stop()
            if (root._active) root._releaseHold.restart()
            else root._deactivate()
        }
    }
    // the moment Home starts fading out, on a close or a tab switch, it stops wanting these: clearing then
    // blanked its tiles (CPU to a dash, its wave, the busiest process) on the first frame of the fade
    property Timer _releaseHold: Timer { interval: 300; onTriggered: if (!root._wanted) root._deactivate() }
    property Timer _topRelease: Timer { interval: 300; onTriggered: if (!root._topWanted) root._clearTop() }
    on_HomeWantedChanged: {
        if (!root._active) return
        if (root._homeWanted) root._refreshSlow()
        else _uptimePoll.stop()
    }
    on_CpuWantedChanged: {
        if (!root._active || !root._cpuWanted) return
        root._clearCpuSample()
        _cpuPrime.restart()
    }
    on_MemoryWantedChanged: if (!root._memoryWanted) root._vmstat = ""

    function _activate(): void {
        if (_active) return
        _active = true
        cpuReady = false
        if (_homeWanted) _refreshSlow()
        // the file loads as soon as it has a reader; prime a second sample so CPU appears quickly
        if (root._cpuWanted) _cpuPrime.restart()
    }

    function _deactivate(): void {
        root._releaseHold.stop()
        _startDelay.stop()
        _cpuPrime.stop()
        _uptimePoll.stop()
        _active = false
        root._clearCpuSample()
        root._clearTop()
        if (_slowProc.running) _slowProc.running = false
    }

    // created lazily on first open, after open already flipped true, catch that missed edge
    Component.onCompleted: if (_wanted) _startDelay.restart()

    Timer { id: _startDelay; interval: 120; onTriggered: root._activate() }
    Timer { id: _cpuPrime; interval: 250; onTriggered: if (root._active && root._cpuWanted) _statFile.reload() }
    property Timer _topPrime: Timer { interval: 1000; onTriggered: if (root._topWanted) root._sampleTop() }
    Timer { id: _uptimePoll; onTriggered: if (root._active && root._homeWanted) _uptimeFile.reload() }

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
        running: root._active && root._homeWanted
        onTriggered: root._refreshSlow()
    }

    FileView {
        id: _meminfoFile
        path: root._active && root._memoryWanted ? "/proc/meminfo" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._memoryWanted) root._applyMeminfo(_meminfoFile.text())
        onLoadFailed: if (root._active && root._memoryWanted) {
            root.memTotalKb = 0; root.memAvailKb = 0
            root.swapTotalKb = 0; root.swapUsedKb = 0
        }
    }

    // absent before the kernel counted this pool, which leaves the reading as MemAvailable gives it
    FileView {
        id: _vmstatFile
        path: root._active && root._memoryWanted ? "/proc/vmstat" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._memoryWanted) root._vmstat = _vmstatFile.text()
        onLoadFailed: root._vmstat = ""
    }

    // absent on a kernel built without PSI, which simply leaves swap unreported
    FileView {
        id: _pressureFile
        path: root._active && root._memoryWanted ? "/proc/pressure/memory" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._memoryWanted) root._applyPressure(_pressureFile.text())
        onLoadFailed: if (root._active && root._memoryWanted) root._applyPressure("")
    }

    FileView {
        id: _uptimeFile
        path: root._active && root._homeWanted ? "/proc/uptime" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._homeWanted) root._applyUptime(_uptimeFile.text())
        onLoadFailed: {
            if (!root._active || !root._homeWanted) return
            _uptimePoll.interval = 2000
            _uptimePoll.restart()
        }
    }

    FileView {
        id: _statFile
        path: root._active && root._cpuWanted ? "/proc/stat" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: if (root._cpuWanted) root._applyCpuStat(_statFile.text())
        onLoadFailed: if (root._active && root._cpuWanted) root._clearCpuSample()
    }

    function _refreshFast(): void {
        if (!_active) return
        if (root._memoryWanted) {
            _vmstatFile.reload()
            _meminfoFile.reload()
            _pressureFile.reload()
        }
        if (root._cpuWanted) _statFile.reload()
        if (root._topWanted) root._sampleTop()
    }

    property string _vmstat: ""

    // freed GPU buffers the driver keeps and hands back under pressure. MemAvailable leaves them out, which
    // read as a third of all memory in use on a desktop with free GB to spare
    function gpuReclaimKb(vmstat: string, mem: string): real {
        const reclaim = vmstat.match(/^nr_gpu_reclaim (\d+)$/m)
        if (!reclaim) return 0
        // vmstat counts pages; page tables are the one figure both files give, so their ratio is the page size
        const tablesKb = mem.match(/^PageTables:\s+(\d+)/m)
        const tablePages = vmstat.match(/^nr_page_table_pages (\d+)$/m)
        const pageKb = tablesKb && tablePages && Number(tablePages[1]) > 0
            ? Math.max(1, Math.round(Number(tablesKb[1]) / Number(tablePages[1]))) : 4
        return Number(reclaim[1]) * pageKb
    }

    function _applyMeminfo(mem: string): void {
        if (!root._active) return
        const total = mem.match(/^MemTotal:\s+(\d+)/m)
        const avail = mem.match(/^MemAvailable:\s+(\d+)/m)
        const totalKb = total ? Number(total[1]) : 0
        const availKb = avail ? Number(avail[1]) : NaN
        const memTotal = isFinite(totalKb) && totalKb > 0 && isFinite(availKb) ? totalKb : 0
        // the total lands last, and goes first when the reading fails: either other way the percentage passed
        // through 100% used, and the bar's monitor grew for it and held the width for its shrink delay
        if (memTotal > 0) {
            root.memAvailKb = Math.max(0, Math.min(memTotal, availKb + root.gpuReclaimKb(root._vmstat, mem)))
            root.memTotalKb = memTotal
        } else {
            root.memTotalKb = 0
            root.memAvailKb = 0
        }
        // SwapFree, not SwapCached: cached pages are still resident, only used = total - free is pressure
        const swapTotal = mem.match(/^SwapTotal:\s+(\d+)/m)
        const swapFree = mem.match(/^SwapFree:\s+(\d+)/m)
        const swapTotalKb = swapTotal ? Number(swapTotal[1]) : 0
        const swapFreeKb = swapFree ? Number(swapFree[1]) : NaN
        root.swapTotalKb = isFinite(swapTotalKb) && swapTotalKb > 0 && isFinite(swapFreeKb) ? swapTotalKb : 0
        root.swapUsedKb = root.swapTotalKb > 0
            ? Math.max(0, Math.min(root.swapTotalKb, root.swapTotalKb - swapFreeKb)) : 0
    }

    function _applyPressure(raw: string): void {
        if (!root._active) return
        const some = raw.match(/^some avg10=([0-9.]+)/m)
        const pressure = some ? Number(some[1]) : 0
        root.memPressure = isFinite(pressure) ? pressure : 0
        root._memStalled = root.memPressure >= 10 || (root._memStalled && root.memPressure >= 5)
    }

    function _applyUptime(raw: string): void {
        if (!root._active) return
        const up = raw.trim().split(/\s+/)
        root.uptimeSecs = parseFloat(up[0]) || 0
        if (!root._homeWanted) return
        _uptimePoll.interval = root.uptimeSecs < 60 ? 2000
            : Math.max(1000, Math.ceil((60 - root.uptimeSecs % 60) * 1000) + 100)
        _uptimePoll.restart()
    }

    function _clearCpuSample(): void {
        root.cpuReady = false
        root.cpuPct = 0
        root.cpuHigh = false
        root._cpuBusySamples = 0
        root._lastCpuTotal = 0
        root._lastCpuIdle = 0
    }

    function _updateCpuLoad(): void {
        // count samples, including identical readings at 100%; property-change
        // handlers miss those, and each monitor must see the same warning
        if (root.cpuReady && root.cpuPct >= 0.90) {
            root._cpuBusySamples = Math.min(2, root._cpuBusySamples + 1)
            if (root._cpuBusySamples >= 2) root.cpuHigh = true
        } else {
            root._cpuBusySamples = 0
            if (!root.cpuReady || root.cpuPct < 0.75) root.cpuHigh = false
        }
    }

    function _cpuCounters(line: string): var {
        const fields = line.trim().split(/\s+/)
        if (fields.length < 9 || fields[0] !== "cpu") return null
        let total = 0
        for (let i = 1; i <= 8; i++) {
            if (!/^[0-9]+$/.test(fields[i])) return null
            total += Number(fields[i])
        }
        // user and nice already include the guest columns
        return isFinite(total) ? { total: total, idle: Number(fields[4]) + Number(fields[5]) } : null
    }

    function _cpuLoad(total: real, idle: real, lastTotal: real, lastIdle: real): real {
        const delta = total - lastTotal
        const idleDelta = idle - lastIdle
        // a changed accounting baseline cannot substantiate a load for this interval
        return lastTotal > 0 && delta > 0 && idleDelta >= 0 && idleDelta <= delta
            ? (delta - idleDelta) / delta : -1
    }

    function _applyCpuStat(raw: string): void {
        if (!root._active) return
        const sample = root._cpuCounters(raw.split("\n", 1)[0])
        if (!sample) {
            root._clearCpuSample()
            return
        }
        const load = root._cpuLoad(sample.total, sample.idle, root._lastCpuTotal, root._lastCpuIdle)
        root.cpuReady = load >= 0
        root.cpuPct = Math.max(0, load)
        root._lastCpuTotal = sample.total
        root._lastCpuIdle = sample.idle
        const cores = raw.match(/^cpu[0-9]+ /gm)
        root._cpuCount = cores ? cores.length : 1
        root._updateCpuLoad()
    }

    // per-process ticks against the aggregate over the same interval
    function processSample(raw: string): var {
        const lines = raw.split("\n")
        const cpu = root._cpuCounters(lines[0])
        if (!cpu) return null
        const processes = Object.create(null)
        let cpus = 0
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i]
            if (line.startsWith("cpu")) {
                if (/^cpu[0-9]+ /.test(line)) cpus++
                continue
            }
            const open = line.indexOf(" (")
            const close = line.lastIndexOf(") ")
            if (open <= 0 || close < open) continue
            const pid = line.slice(0, open)
            if (!/^[0-9]+$/.test(pid)) continue
            // fields 4, 14, 15 and 22: the parent, user ticks, system ticks and the process start time
            const fields = /^[^ ]+ (\d+) (?:[^ ]+ ){9}(\d+) (\d+) (?:[^ ]+ ){6}(\d+)(?: |$)/.exec(line.slice(close + 2))
            if (!fields) continue
            const ticks = Number(fields[2]) + Number(fields[3])
            if (isFinite(ticks)) processes[pid] = { ticks: ticks, started: fields[4], ppid: fields[1],
                name: line.slice(open + 2, close) }
        }
        return { total: cpu.total, idle: cpu.idle, cpus: Math.max(1, cpus), processes: processes }
    }

    function busiestProcess(last, next): var {
        if (!last || !next || last.cpus !== next.cpus) return null
        const load = root._cpuLoad(next.total, next.idle, last.total, last.idle)
        if (load < 0) return null
        let pid = "", most = 0
        for (const id in next.processes) {
            const before = last.processes[id]
            const after = next.processes[id]
            if (!before || before.started !== after.started) continue
            const used = after.ticks - before.ticks
            if (used > most) { most = used; pid = id }
        }
        if (pid.length === 0) return null
        const share = Math.min(1, most / (next.total - last.total))
        const process = next.processes[pid]
        return { pid: Number(pid), started: process.started, name: SafeText.singleLineText(process.name, 32),
            share: share, cores: share * next.cpus, load: load }
    }

    // a busy machine, or one process holding a core, for two samples in a row; it eases out under a lower line
    function topSamplesAfter(busiest, cpuPct: real, samples: int): int {
        if (!busiest) return 0
        if (cpuPct >= 0.5 || busiest.cores >= 0.9) return Math.min(2, samples + 1)
        return samples >= 2 && (cpuPct >= 0.35 || busiest.cores >= 0.6) ? 2 : 0
    }
    // a process uses at most what the whole machine does, so under topSamplesAfter's lower line no name can show or stay
    function topPossible(ready: bool, cpuPct: real, cpus: int): bool {
        return ready && (cpuPct >= 0.35 || cpuPct * Math.max(1, cpus) >= 0.6)
    }

    // comm is cut at 15 and Node and Firefox rename their main threads ("node-MainThread"); a whole comm stays,
    // since Steam's helpers start from a launcher path ending in "exe"
    function commandName(cmdline: string, comm: string): string {
        let argv = String(cmdline || "").split("\u0000").filter(arg => arg.length > 0)
        // Firefox joins its arguments into one string: its path, then flags. A lone path can hold a space
        // ("…/common/Some Game/game"), and a title a program wrote ("sshd: user@pts/0") has no path at all
        if (argv.length === 1 && /^\/\S+\s+-/.test(argv[0])) argv = argv[0].split(/\s+/)
        if (argv.length === 0 || /\s/.test(argv[0])) return comm
        const base = arg => arg.split(/[\\/]/).pop()
        const interpreter = /^(node|nodejs|bun|deno|python[0-9.]*|ruby|perl|php|bash|sh)$/
        // a login shell's argv[0] is its name after a dash: as an interpreter's own, "-bash" was shown as the name
        let name = base(argv[0]).replace(/^-/, "")
        if (interpreter.test(name) && argv.length > 1 && !argv[1].startsWith("-")) name = base(argv[1])
        if (name.length === 0 || name === comm) return comm
        // wine names a Windows program's process after its main thread ("Main"), so the .exe its command line runs wins
        const cut = comm.length >= 15 || name.startsWith(comm) || interpreter.test(comm) || /\.exe$/i.test(name)
        return cut ? SafeText.singleLineText(name, 32) : comm
    }
    // the app a busy process works for: the window it owns, or the nearest window up its parents when that one runs
    // the same program (a browser's content process, an Electron renderer). Another program's window, a terminal's,
    // leaves a build or a script under its own name
    function windowApp(processes, pid: int, program: string, windows): string {
        if (!processes || !processes[pid] || !windows || windows.length === 0) return ""
        const owners = Object.create(null)
        for (const w of windows) if (w && w.pid > 0 && w.appId) owners[w.pid] = String(w.appId)
        const names = [processes[pid].name, String(program || "").slice(0, 15)]
        let at = String(pid)
        for (let depth = 0; depth < 32 && processes[at]; depth++) {
            const appId = owners[at]
            if (appId) return at === String(pid) || names.indexOf(processes[at].name) >= 0 ? appId : ""
            at = processes[at].ppid
        }
        return ""
    }
    // as its launcher names it ("Firefox", a Steam game's title), else the program
    function _nameFor(pid: int, comm: string, program: string): string {
        const appId = root.windowApp(root._topLast ? root._topLast.processes : null, pid, program, Compositor.toplevels)
        const entry = appId.length > 0 ? IconResolver.appEntry(appId) : null
        const app = entry ? SafeText.singleLineText(entry.name, 32) : ""
        return app.length > 0 ? app : program.length > 0 ? program : comm
    }
    // read for the first busy sample's pick, so the name is there when the second one shows it
    property int _cmdlinePid: 0
    property string _cmdlineStart: ""
    property string _cmdlineComm: ""
    property int _cmdNamePid: 0
    property string _cmdName: ""
    FileView {
        id: _cmdlineFile
        path: root._cmdlinePid > 0 ? "/proc/" + root._cmdlinePid + "/cmdline" : ""
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            root._cmdNamePid = root._cmdlinePid
            root._cmdName = root.commandName(_cmdlineFile.text(), root._cmdlineComm)
            if (root.topShown && root.topPid === root._cmdNamePid && root._cmdName.length > 0)
                root.topName = root._nameFor(root._cmdNamePid, root._cmdlineComm, root._cmdName)
        }
        onLoadFailed: root._cmdNamePid = 0
    }

    function _applyTop(sample): void {
        const busiest = root.busiestProcess(root._topLast, sample)
        root._topLast = sample
        root._topSamples = root.topSamplesAfter(busiest, busiest?.load ?? 0, root._topSamples)
        root.topShown = root._topSamples >= 2
        if (busiest && (busiest.pid !== root._cmdlinePid || busiest.started !== root._cmdlineStart
                || busiest.name !== root._cmdlineComm)) {
            root._cmdNamePid = 0
            root._cmdlineStart = busiest.started
            root._cmdlineComm = busiest.name
            if (busiest.pid === root._cmdlinePid) _cmdlineFile.reload()
            else root._cmdlinePid = busiest.pid
        }
        root.topName = !root.topShown ? ""
            : root._nameFor(busiest.pid, busiest.name, root._cmdNamePid === busiest.pid ? root._cmdName : "")
        root.topPid = root.topShown ? busiest.pid : 0
    }

    function _startTop(): void {
        if (!root._topPossible) return
        root._sampleTop()
        root._topPrime.restart()
    }

    function _sampleTop(): bool {
        if (_topProc.running || !root._topPossible) return false
        _topProc.exec(["sh", "-c", "exec cat /proc/stat /proc/[0-9]*/stat 2>/dev/null"])
        return true
    }

    function _clearTop(): void {
        root._topPrime.stop()
        if (_topProc.running) _topProc.running = false
        root._topLast = null
        root._topSamples = 0
        root.topShown = false
        root.topName = ""
        root.topPid = 0
        root._cmdlinePid = 0
        root._cmdlineStart = ""
        root._cmdlineComm = ""
        root._cmdNamePid = 0
    }

    BoundedProcess {
        id: _topProc
        timeoutMs: 3000
        stdout: StdioCollector { id: _topOut }
        onExited: if (!_topProc.timedOut && root._topWanted) root._applyTop(root.processSample(_topOut.text))
        Component.onDestruction: running = false
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
        // -P keeps the device on one line. Read from the right to allow spaces in it
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
