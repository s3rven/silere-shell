import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// the same readings as Home's system rows, at a glance. Sampling follows the widget:
// switched off, idle or under the overview, nothing reads /proc
Pill {
    id: root
    property var screen: null

    readonly property bool _cpuOn: ShellSettings.systemShowCpu
    readonly property bool _memOn: ShellSettings.systemShowMemory
    // no sensor means no reading ever: drop the slot rather than hold a dash, and the pill when it was the only one
    readonly property bool _tempOn: ShellSettings.systemShowTemp && !CpuTemp.sensorMissing
    readonly property bool show: ShellSettings.barShowSystem && (_cpuOn || _memOn || _tempOn)
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
            parts.push({ glyph: "󰘚", value: root.percent(root._mem), reserve: "00%",
                detail: root._mem < 0 ? "—"
                    : root.gigabytes(used) + " of " + root.gigabytes(SysInfo.memTotalKb)
                        + (SysInfo.swapActive ? " · " + root.gigabytes(SysInfo.swapUsedKb) + " swap" : ""),
                level: root._memLevel,
                spoken: "memory " + root.percent(root._mem)
                    + (SysInfo.swapActive ? ", " + root.gigabytes(SysInfo.swapUsedKb) + " swap" : "") })
        }
        if (root._tempOn) {
            const t = root._temp < 0 ? "—" : Math.round(root._temp) + "°"
            parts.push({ glyph: "󰔏", value: t, reserve: "00°", detail: t + "C", level: root._tempLevel,
                spoken: "temperature " + t + "C" })
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
    maxTextWidth: compact ? 160 : 280

    text: !root._readingsShown || root._parts.length === 0 ? ""
        : root.expanded ? root._parts[0].detail : root._parts[0].value
    segments: !root._readingsShown ? [] : root._parts.slice(1).map(p => ({
        glyph: p.glyph, text: root.expanded ? p.detail : p.value, reserve: p.reserve,
        color: root._levelTint(p.level) }))
    accessibleName: "System, " + root._parts.map(p => p.spoken).join(", ")
        + (root.severity === 2 ? ", critical" : root.severity === 1 ? ", high" : "")

    interactive: root.show
    pressed: _tap.pressed
    onActivated: if (root.canActivate) MenuState.showTabAt(MenuState.homeTab, root, root.screen)
    hasSecondary: Settings.systemMonitorCommand.length > 0
    onSecondaryActivated: SystemTools.runOrNotify(Settings.systemMonitorCommand, "System monitor failed to start")
    TapHandler {
        id: _tap
        enabled: root.canActivate
        onTapped: root.activated()
    }
}
