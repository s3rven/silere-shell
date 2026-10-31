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
    readonly property bool _tempOn: ShellSettings.systemShowTemp
    readonly property bool show: ShellSettings.barShowSystem && (_cpuOn || _memOn || _tempOn)
    collapsed: !show
    visible: show || opacity > 0.001
    opacity: show ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }

    readonly property real _cpu: root._cpuOn && SysInfo.cpuReady ? SysInfo.cpuPct : -1
    readonly property real _mem: root._memOn && SysInfo.memTotalKb > 0 ? SysInfo.memPct : -1
    readonly property real _temp: root._tempOn && CpuTemp.available ? CpuTemp.temp : -1

    // a build pins the CPU for a while and a single busy tick is not news: the tint
    // needs a sustained reading and lets go only well below it, so it never flickers
    property bool _cpuHigh: false
    property int _cpuBusySamples: 0
    on_CpuChanged: {
        if (root._cpu >= 0.90) {
            root._cpuBusySamples++
            if (root._cpuBusySamples >= 2) root._cpuHigh = true
        } else if (root._cpu < 0.75) {
            root._cpuBusySamples = 0
            root._cpuHigh = false
        }
    }
    // memory uses Home's own bands, so the two never disagree about the same reading
    readonly property int severity: (root._temp >= 0 && CpuTemp.critical) || root._mem > 0.9 ? 2
        : root._cpuHigh || root._mem > 0.75 || (root._temp >= 0 && CpuTemp.hot) ? 1 : 0

    function percent(value: real): string {
        return value < 0 ? "—" : Math.round(value * 100) + "%"
    }
    function gigabytes(kb: real): string {
        const gb = kb / 1048576
        return (gb < 10 ? gb.toFixed(1) : String(Math.round(gb))) + " GB"
    }

    readonly property var _parts: {
        const parts = []
        if (root._cpuOn) parts.push({ glyph: "󰍛", value: root.percent(root._cpu),
            detail: "CPU " + root.percent(root._cpu), spoken: "CPU " + root.percent(root._cpu) })
        if (root._memOn) {
            const used = SysInfo.memTotalKb - SysInfo.memAvailKb
            parts.push({ glyph: "󰘚", value: root.percent(root._mem),
                detail: root._mem < 0 ? "Memory —"
                    : root.gigabytes(used) + " of " + root.gigabytes(SysInfo.memTotalKb)
                        + (SysInfo.swapActive ? " · " + root.gigabytes(SysInfo.swapUsedKb) + " swap" : ""),
                spoken: "memory " + root.percent(root._mem)
                    + (SysInfo.swapActive ? ", " + root.gigabytes(SysInfo.swapUsedKb) + " swap" : "") })
        }
        if (root._tempOn) {
            const t = root._temp < 0 ? "—" : Math.round(root._temp) + "°"
            parts.push({ glyph: "󰔏", value: t, detail: t + "C", spoken: "temperature " + t + "C" })
        }
        return parts
    }

    glyph: root._parts.length > 0 ? root._parts[0].glyph : "󰍛"
    glyphColor: root.severity === 2 ? Theme.error : root.severity === 1 ? Theme.warning : Theme.text
    textColor: Theme.subtext
    animateGlyph: false
    // two digits per reading: the pill keeps its width as values tick, and only grows at 100%
    reserveText: root._parts.map((p, i) => (i > 0 ? p.glyph + " " : "") + "00%").join("  ")
    // above the 2 s poll, so a reading that shortens does not re-animate the width every tick
    shrinkDelay: 2400
    maxTextWidth: compact ? 160 : 280

    text: {
        if (ShellSettings.valuesOnHover && !root.expanded) return ""
        if (root.expanded) return root._parts.map(p => p.detail).join(" · ")
        return root._parts.map((p, i) => (i > 0 ? p.glyph + " " : "") + p.value).join("  ")
    }
    accessibleName: "System, " + root._parts.map(p => p.spoken).join(", ")
        + (root.severity === 2 ? ", critical" : root.severity === 1 ? ", high" : "")

    interactive: root.show
    pressed: _tap.pressed
    onActivated: if (root.canActivate) MenuState.showTabAt(MenuState.homeTab, root, root.screen)
    TapHandler {
        id: _tap
        enabled: root.canActivate
        onTapped: root.activated()
    }
}
