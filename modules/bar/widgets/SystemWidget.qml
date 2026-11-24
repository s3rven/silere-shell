import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// the same readings as Home's system rows, at a glance. Sampling follows the widget:
// switched off, idle or under the overview, nothing reads /proc
Pill {
    id: root
    property var screen: null
    property real layoutWidthBudget: -1

    readonly property bool _cpuOn: ShellSettings.systemShowCpu
    readonly property bool _memOn: ShellSettings.systemShowMemory
    // no sensor means no reading ever: drop the slot rather than hold a dash, and the pill when it was the only one
    readonly property bool _tempOn: ShellSettings.systemShowTemp && !CpuTemp.sensorMissing
    readonly property bool show: ShellSettings.barShowSystem && SysInfo.monitorHasReadings
    readonly property bool layoutVisible: show || opacity > 0.001
    collapsed: !show
    visible: layoutVisible
    opacity: show ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }

    readonly property real _cpu: root._cpuOn && SysInfo.cpuReady ? SysInfo.cpuPct : -1
    readonly property real _mem: root._memOn && SysInfo.memTotalKb > 0 ? SysInfo.memPct : -1
    readonly property real _temp: root._tempOn && CpuTemp.available ? CpuTemp.reading : -1

    readonly property bool _busiestWanted: root.show && root._cpuOn && root.expanded
    on_BusiestWantedChanged: SysInfo.requestTopProcess(root, root._busiestWanted)
    Component.onDestruction: SysInfo.requestTopProcess(root, false)
    readonly property string _busiest: root._cpu >= 0 && SysInfo.topShown
        ? SysInfo.topName + " (" + SysInfo.topPid + ")" : ""
    // a part coming or going from the detail is not a reading that flickers: held for the shrink delay, a busiest
    // process going left 120 px of empty pill for 2.4 s. Another process taking its place is still held
    readonly property int _detailParts: (root._busiest.length > 0 ? 1 : 0) + (root._memOn && SysInfo.swapActive ? 2 : 0)
    on_DetailPartsChanged: root._releaseHold()

    readonly property int _cpuLevel: root._cpuOn && SysInfo.cpuReady && SysInfo.cpuHigh ? 1 : 0
    // memory reads Home's own band, so the two never disagree about the same reading
    readonly property int _memLevel: root._mem < 0 ? 0 : SysInfo.memLevel
    readonly property int _tempLevel: root._temp < 0 ? 0 : CpuTemp.critical ? 2 : CpuTemp.hot ? 1 : 0
    readonly property int severity: Math.max(root._cpuLevel, root._memLevel, root._tempLevel)
    function _levelTint(level: int, ready: bool): color {
        return level === 2 ? Theme.barError : level === 1 ? Theme.barWarning
            : ready ? Theme.barText : Theme.barSubtext
    }
    readonly property bool _rings: ShellSettings.systemRings
    function _ringTint(level: int): color {
        return level === 2 ? Theme.barError : level === 1 ? Theme.barWarning : Theme.barAccentMark
    }

    function percent(value: real): string {
        return value < 0 ? "—" : Math.round(value * 100) + "%"
    }
    function gigabytes(kb: real): string {
        const gb = kb / 1048576
        return (gb < 10 ? gb.toFixed(1) : String(Math.round(gb))) + " GB"
    }

    readonly property var _parts: {
        const parts = []
        // two digits reserved per reading: the pill keeps its width as values tick, and only grows at 100%
        if (root._cpuOn) parts.push({ glyph: "󰍛", value: root.percent(root._cpu), reserve: "00%",
            detail: root.percent(root._cpu) + (root._busiest.length > 0 ? " · " + root._busiest : ""),
            ready: root._cpu >= 0, level: root._cpuLevel, ring: Math.max(0, root._cpu),
            spoken: root._cpu < 0 ? "CPU usage unavailable"
                : "CPU " + root.percent(root._cpu) + (root._busiest.length > 0 ? ", most by " + SysInfo.topName : "") })
        if (root._memOn) {
            const used = SysInfo.memTotalKb - SysInfo.memAvailKb
            const amount = root._mem < 0 ? "—"
                : root.gigabytes(used) + " of " + root.gigabytes(SysInfo.memTotalKb)
            const swap = SysInfo.swapActive ? root.gigabytes(SysInfo.swapUsedKb) + " swap" : ""
            parts.push({ glyph: "󰘚", value: root.percent(root._mem), reserve: "00%",
                shortDetail: amount,
                detail: root._mem >= 0 && swap.length > 0 ? amount + " · " + swap : amount,
                ready: root._mem >= 0, level: root._memLevel, ring: Math.max(0, root._mem),
                spoken: root._mem < 0 ? "memory usage unavailable" : "memory " + root.percent(root._mem)
                    + ", " + amount + (swap.length > 0 ? ", " + swap : "") })
        }
        if (root._tempOn) {
            const t = root._temp < 0 ? "—" : Math.round(root._temp) + "°"
            // a ring on the 0 to 100 °C scale: the warning lines sit high on it, where a full ring reads as hot
            parts.push({ glyph: "󰔏", value: t, reserve: "00°", shortDetail: t,
                detail: root._temp < 0 ? t : t + "C",
                ready: root._temp >= 0, level: root._tempLevel,
                ring: Math.max(0, Math.min(1, root._temp / 100)),
                spoken: root._temp < 0 ? "CPU temperature unavailable"
                    : "CPU temperature " + Math.round(root._temp) + " degrees Celsius" })
        }
        return parts
    }

    // resting as the glyph alone, it speaks for every reading; beside the readings, each glyph speaks for its own
    readonly property bool _readingsShown: !ShellSettings.valuesOnHover || root.expanded
    glyph: root._parts.length > 0 ? root._parts[0].glyph : "󰍛"
    glyphColor: (root._readingsShown || root._rings) && root._parts.length > 0
        ? root._levelTint(root._parts[0].level, root._parts[0].ready)
        : root._levelTint(root.severity, root._parts.some(p => p.ready))
    glyphRing: root._rings && root._parts.length > 0 ? root._parts[0].ring : -1
    glyphRingColor: root._ringTint(root._parts.length > 0 ? root._parts[0].level : 0)
    textColor: Theme.barSubtext
    animateGlyph: false
    reserveText: root._parts.length > 0 ? root._parts[0].reserve : ""
    // above the 2 s poll, so a reading that shortens does not re-animate the width every tick
    shrinkDelay: 2400
    readonly property int _detailLimit: compact ? 160 : 280
    readonly property var _readingWidths: {
        if (root.layoutWidthBudget < 0) return root._parts.map(() => root._detailLimit)
        const cell = root._rings ? root.ringSize : Metrics.iconCellFor(root.glyphPixelSize)
        const between = root._gap + Math.round(root._gap / 2)
        const count = root._parts.length
        let available = root.layoutWidthBudget - 2 * root.horizontalPadding
            - count * cell - Math.max(0, count - 1) * between
        let shown = 0
        // fit complete readings before offering any room to their longer hover text
        const widths = root._parts.map(part => {
            const minimum = Math.max(root._readoutWidth(part.value), root._readoutWidth(part.reserve))
            if (minimum + root._gap > available) return 0
            available -= minimum + root._gap
            shown++
            return minimum
        })
        const extra = shown > 0 ? Math.floor(available / shown) : 0
        return widths.map(width => width > 0 ? Math.min(root._detailLimit, width + extra) : 0)
    }
    on_ReadingWidthsChanged: if (root.layoutWidthBudget >= 0
            && root._minW > root.layoutWidthBudget - root.horizontalPadding * 2) root._releaseHold()
    maxTextWidth: root._readingWidths[0] ?? 0

    FontMetrics {
        id: _readoutFont
        font.family: Settings.font
        font.pixelSize: Settings.fontSize
        font.features: ({ "tnum": 1 })
    }

    function _readoutWidth(text: string): int {
        void _readoutFont.font
        return Math.ceil(_readoutFont.advanceWidth(text)) + 1
    }

    function _readout(part, width: int): string {
        if (!root._readingsShown || width <= 0) return ""
        if (!root.expanded) return part.value
        const base = part.shortDetail ?? part.value
        // keep the amount or percentage legible before adding a process or swap usage
        if (root._readoutWidth(base) > width) return part.value
        if (part.shortDetail !== undefined && root._readoutWidth(part.detail) > width)
            return base
        if (part.shortDetail === undefined && width < root._readoutWidth(base) + Settings.fontSize)
            return base
        return part.detail
    }

    text: root._parts.length > 0 ? root._readout(root._parts[0], root.maxTextWidth) : ""
    // an empty reserve with the text: a held reserve would leave a reading's gap after each ring
    segments: !root._readingsShown && !root._rings ? [] : root._parts.slice(1).map((p, index) => {
        const width = root._readingWidths[index + 1] ?? 0
        return { glyph: p.glyph, text: root._readout(p, width), maxTextWidth: width,
            reserve: root._readingsShown && width > 0 ? p.reserve : "", color: root._levelTint(p.level, p.ready),
            ring: root._rings ? p.ring : -1, ringColor: root._ringTint(p.level) }
    })
    accessibleName: "System, " + root._parts.map(p => p.spoken).join(", ")
        + (root.severity === 2 ? ", critical" : root.severity === 1 ? ", high" : "")

    interactive: root.show
    pressed: _tap.pressed
    onActivated: if (root.canActivate) MenuState.showTabAt(MenuState.homeTab, root, root.screen)
    hasSecondary: Settings.systemMonitorCommand.length > 0
    onSecondaryActivated: SystemAlerts.runOrNotify(Settings.systemMonitorCommand, "System monitor failed to start")
    TapHandler {
        id: _tap
        enabled: root.canActivate
        onTapped: root.activated()
    }
}
