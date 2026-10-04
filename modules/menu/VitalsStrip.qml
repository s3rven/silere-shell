import QtQuick
import "../../config"
import "../../services"
import "../common"

// static layout + in-place bindings: no Repeater model or Canvas that would rebuild every 60fps alert poll
Rectangle {
    id: root

    property bool active: true
    readonly property int _pad: 7

    function sizeText(kb: real): string {
        if (!isFinite(kb) || kb <= 0) return ""
        const units = ["K", "M", "G", "T"]
        let v = kb, i = 0
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
        const tenths = Math.round(v * 10) / 10
        return (tenths < 10 ? tenths.toFixed(1) : String(Math.round(v))) + units[i]
    }

    width: parent ? parent.width : 0
    implicitHeight: _grid.implicitHeight + 2 * _pad
    height: implicitHeight
    radius: Theme.radiusCard
    antialiasing: true
    color: Theme.menuCard

    OutlineBorder {
        radius: root.radius
        outlineColor: Theme.menuCardBorder
    }

    component Vital: Item {
        id: tile

        property string glyph: ""
        property string label: ""
        property string value: ""
        property string sub: ""
        property string reserveSub: ""
        property real   progress: 0
        property int    status: 0
        property real   pulse: 0
        property bool   live: true
        property bool   divider: true
        readonly property int padL: divider ? 18 : 14
        property int          padR: 18

        readonly property color tint: status === 2 ? Theme.error
                                    : status === 1 ? Theme.warning
                                    : Theme.menuTextMuted

        height: Metrics.rowHeightFor(70)
        // reserve the widest readings so 99 -> 100 never changes the column count
        implicitWidth: 36 + Math.max(_labelRow.implicitWidth,
            _valueMetrics.advanceWidth + (tile.sub.length > 0
                ? 4 + Math.max(_subMetrics.advanceWidth, _sub.implicitWidth) : 0))

        TextMetrics { id: _valueMetrics; font: _val.font; text: "100%" }
        TextMetrics { id: _subMetrics; font: _sub.font; text: tile.reserveSub }

        // whole percent like the readout: every poll's fraction ran the glide, and a running glide redraws every window
        readonly property real _p: Math.round(Math.max(0, Math.min(1, progress)) * 100) / 100
        property real _disp: _p
        MotionBehavior on _disp {
            id: _glide
            // a step under five points moves the bar a pixel or two; snap it rather than redraw every window
            gate: tile.live && Math.abs(_glide.targetValue - tile._disp) >= 0.05
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: tile.divider
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(parent.height * 0.52)
            color: Theme.withAlpha(Theme.subtext, 0.10)
        }

        Row {
            id: _labelRow
            anchors.left: parent.left
            anchors.leftMargin: tile.padL
            y: 11
            spacing: 4

            ShellText {
                id: _gl
                text: tile.glyph
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.menuTextMuted, tile.tint, 0.36 + tile.pulse * 0.38)
                    : Theme.withAlpha(Theme.menuTextMuted, 0.82)
                font.pixelSize: Settings.fontMicro
            }
            ShellText {
                anchors.baseline: _gl.baseline
                text: tile.label
                color: Theme.withAlpha(Theme.menuTextMuted, 0.82)
                font.pixelSize: Settings.fontMicro
                font.letterSpacing: 0.4
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
            }
        }

        Row {
            id: _valueRow
            anchors.left: parent.left
            anchors.leftMargin: tile.padL
            anchors.top: _labelRow.bottom
            anchors.topMargin: 3
            spacing: 4

            ShellText {
                id: _val
                text: tile.value
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.text, tile.tint, tile.pulse * 0.5)
                    : tile.status > 0
                        ? Theme.mix(Theme.text, tile.tint, 0.45)
                        : Theme.withAlpha(Theme.text, 0.92)
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
            }
            ShellText {
                id: _sub
                visible: tile.sub !== ""
                anchors.baseline: _val.baseline
                text: tile.sub
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.menuTextMuted, tile.tint, tile.pulse * 0.6)
                    : Theme.withAlpha(Theme.menuTextMuted, 0.85)
                font.pixelSize: Settings.fontLabel
            }
        }

        Rectangle {
            anchors.left: parent.left;   anchors.leftMargin: tile.padL
            anchors.right: parent.right; anchors.rightMargin: tile.padR
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            height: 4
            radius: 2
            antialiasing: true
            color: Theme.menuTrack

            Rectangle {
                width: tile._disp <= 0 ? 0 : Math.max(parent.height, Math.round(parent.width * tile._disp))
                height: parent.height
                radius: parent.radius
                antialiasing: true
                color: tile.status > 0 ? tile.tint : Theme.withAlpha(Theme.accent, 0.70)
                ColorFade on color {}
            }
        }
    }

    Grid {
        id: _grid
        y: root._pad
        width: parent.width
        readonly property int naturalCells: Battery.available ? 4 : 3
        readonly property int minCellW: Metrics.snap4Up(Math.max(80,
            _cpu.implicitWidth, _memory.implicitWidth, _disk.implicitWidth,
            _battery.visible ? _battery.implicitWidth : 0))
        readonly property int cells: width >= naturalCells * minCellW ? naturalCells
            : width >= 2 * minCellW ? 2 : 1
        readonly property real cellW: width / cells
        columns: cells

        Vital {
            id: _cpu
            width: _grid.cellW
            live: root.active
            divider: false
            glyph: "󰔏"
            label: "CPU"
            value: SysInfo.cpuReady ? Math.round(SysInfo.cpuPct * 100) + "%" : "—"
            sub: CpuTemp.available ? Math.round(CpuTemp.temp) + "°" : ""
            reserveSub: "125°"
            progress: SysInfo.cpuReady ? SysInfo.cpuPct : 0
            status: CpuTemp.critical ? 2 : (CpuTemp.hot ? 1 : 0)
            pulse: CpuTemp.alertPulse
        }

        Vital {
            id: _memory
            width: _grid.cellW
            live: root.active
            divider: _grid.cells > 1
            glyph: "󰘚"
            label: "Mem"
            value: SysInfo.memTotalKb > 0 ? Math.round(SysInfo.memPct * 100) + "%" : "—"
            sub: SysInfo.memTotalKb > 0 ? root.sizeText(SysInfo.memTotalKb - SysInfo.memAvailKb) : ""
            reserveSub: "999G"
            progress: SysInfo.memPct
            status: SysInfo.memPct > 0.9 ? 2 : (SysInfo.memPct > 0.75 ? 1 : 0)
        }

        Vital {
            id: _disk
            width: _grid.cellW
            live: root.active
            padR: Battery.available ? 18 : 14
            divider: _grid.cells > 2
            glyph: "󰋊"
            label: "Disk"
            value: SysInfo.diskTotalKb > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
            sub: SysInfo.diskTotalKb > 0 && SysInfo.diskAvailKb > 0 ? root.sizeText(SysInfo.diskAvailKb) + " free" : ""
            reserveSub: "999G free"
            progress: SysInfo.diskPct
            status: SysInfo.diskPct > 0.9 ? 2 : (SysInfo.diskPct > 0.75 ? 1 : 0)
        }

        Vital {
            id: _battery
            width: _grid.cellW
            live: root.active
            visible: Battery.available
            divider: _grid.cells > 1
            padR: 14
            glyph: Battery.icon
            label: "Batt"
            value: Battery.available ? Battery.label : "—"
            sub: Battery.timeLabel
            reserveSub: "+ 9h 59m"
            progress: Battery.available ? Math.min(Battery.pct / 100, 1.0) : 0
            status: Battery.critical ? 2 : (Battery.low ? 1 : 0)
            pulse: Battery.alertPulse
        }
    }
}
