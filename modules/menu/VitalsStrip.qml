pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

// static rows + in-place bindings: no Repeater model or Canvas that would rebuild every 60fps alert poll
SettingsCard {
    id: root

    property bool active: true
    readonly property bool _motionAllowed: root.active
        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    on_MotionAllowedChanged: if (!root._motionAllowed) {
        for (const row of [_cpu, _memory, _disk, _battery]) row.settleIntro()
    }
    // only as the menu opens: any running animation redraws the whole window at the display rate, so a replay on every tab switch doubled what the switch cost
    Component.onCompleted: if (root.active) root._introRows()
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open && MenuState.activeTab === MenuState.homeTab) root._introRows()
        }
    }
    function _introRows(): void {
        // the page is still faded out when it turns active, so effective visibility cannot pick the rows
        const rows = Battery.available ? [_cpu, _memory, _disk, _battery] : [_cpu, _memory, _disk]
        for (let i = 0; i < rows.length; i++) rows[i].intro(Motion.ms(40 + 35 * i))
    }
    readonly property int _rowH: Metrics.rowHeightFor(48)

    function sizeText(kb: real): string {
        if (!isFinite(kb) || kb <= 0) return ""
        const units = ["K", "M", "G", "T"]
        let v = kb, i = 0
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
        const tenths = Math.round(v * 10) / 10
        return (tenths < 10 ? tenths.toFixed(1) : String(Math.round(v))) + units[i]
    }

    function batteryDetail(): string {
        if (!Battery.available) return ""
        if (Battery.timeLabel.length === 0) {
            const s = Battery.statusLabel
            return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : ""
        }
        return Battery.charging ? "Full in " + Battery.timeText(Battery.timeToFull, false)
            : Battery.timeLabel + " left"
    }

    component Vital: Item {
        id: tile

        property string glyph: ""
        property string label: ""
        property string value: ""
        property string sub: ""
        property real   progress: 0
        property int    status: 0
        property real   pulse: 0
        property bool   live: true

        readonly property color tint: status === 2 ? Theme.error
                                    : status === 1 ? Theme.warning
                                    : Theme.menuTextMuted

        TextMetrics {
            id: _detailMetrics
            font.family: Settings.font
            font.pixelSize: Settings.fontCaption
            font.weight: Font.Medium
            text: tile.sub
        }

        width: parent ? parent.width : 0
        height: root._rowH
        implicitHeight: height
        Accessible.role: Accessible.StaticText
        Accessible.name: tile.label + " " + tile.value
        Accessible.description: tile.sub

        // the bar grows in from empty each time the page shows; a one-shot, never a loop
        property real _grow: 1
        function settleIntro(): void {
            _introRun.stop()
            tile._grow = 1
        }
        function intro(delay: int): void {
            _introRun.stop()
            if (!Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)) {
                tile._grow = 1
                return
            }
            tile._grow = 0
            _introDelay.duration = delay
            _introRun.restart()
        }
        SequentialAnimation {
            id: _introRun
            PauseAnimation { id: _introDelay; duration: Motion.ms(0) }
            NumberAnimation {
                target: tile; property: "_grow"; to: 1
                duration: Motion.ms(420)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
            }
        }

        // whole percent like the readout: every poll's fraction ran the glide, and a running glide redraws every window
        readonly property real _p: Math.round(Math.max(0, Math.min(1, progress)) * 100) / 100
        property real _disp: _p
        MotionBehavior on _disp {
            id: _glide
            // a step under five points moves the bar a pixel or two; snap it rather than redraw every window
            gate: tile.live && Math.abs(_glide.targetValue - tile._disp) >= 0.05
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Item {
            id: _iconSlot
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18

            ShellText {
                anchors.centerIn: parent
                text: tile.glyph
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.subtext, tile.tint, 0.36 + tile.pulse * 0.38)
                    : tile.status > 0 ? Theme.mix(Theme.subtext, tile.tint, 0.55)
                    : Theme.withAlpha(Theme.subtext, 0.85)
                font.pixelSize: Settings.iconSize + 2
            }
        }

        Column {
            id: _textCol
            anchors.left: _iconSlot.right
            anchors.leftMargin: 10
            anchors.right: _bar.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            ShellText {
                width: parent.width
                text: tile.label
                color: Theme.withAlpha(Theme.text, 0.85)
                font.pixelSize: Settings.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ShellText {
                visible: tile.sub.length > 0
                width: parent.width
                text: tile.sub
                color: tile.status > 0 ? Theme.mix(Theme.menuTextDetail, tile.tint, 0.5)
                    : Theme.menuTextDetail
                font.pixelSize: Settings.fontCaption
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        WaveLine {
            id: _bar
            anchors.right: _val.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            // Give the reading's caption room before sizing its progress bar.
            // Rounding up the text and down the bar avoids fractional elision.
            width: Metrics.snap4Down(Math.max(48, Math.min(136, tile.width * 0.38,
                _val.x - 64 - Math.max(96, Math.ceil(_detailMetrics.advanceWidth) + 1))))
            height: implicitHeight
            value: tile._disp
            reveal: tile._grow
            thickness: 3
            amplitude: 2
            wavelength: 12
            trackColor: Theme.menuTrack
            color: tile.status > 0 ? Theme.withAlpha(tile.tint, 0.85) : Theme.withAlpha(Theme.accent, 0.55)
            ColorFade on color {}
        }

        // reserved at "100%" so 99 -> 100 never shifts the bar; measured as text, not TextMetrics,
        // since distance-field glyphs lay out a fraction wider than their advance
        ShellText { id: _valReserve; visible: false; text: "100%"; font: _val.font }
        ShellText {
            id: _val
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(_valReserve.implicitWidth)
            horizontalAlignment: Text.AlignRight
            text: tile.value
            color: tile.pulse > 0.001
                ? Theme.mix(Theme.text, tile.tint, tile.pulse * 0.5)
                : tile.status > 0
                    ? Theme.mix(Theme.text, tile.tint, 0.45)
                    : Theme.withAlpha(Theme.text, 0.92)
            font.pixelSize: Settings.fontSize
            font.weight: Font.DemiBold
        }
    }

    Vital {
        id: _cpu
        live: root.active
        glyph: "󰔏"
        label: "CPU"
        value: SysInfo.cpuReady ? Math.round(SysInfo.cpuPct * 100) + "%" : "—"
        sub: CpuTemp.available ? Math.round(CpuTemp.temp) + "°" : ""
        progress: SysInfo.cpuReady ? SysInfo.cpuPct : 0
        status: CpuTemp.critical ? 2 : (CpuTemp.hot ? 1 : 0)
        pulse: CpuTemp.alertPulse
    }

    Vital {
        id: _memory
        live: root.active
        glyph: "󰘚"
        label: "Memory"
        value: SysInfo.memTotalKb > 0 ? Math.round(SysInfo.memPct * 100) + "%" : "—"
        sub: SysInfo.memTotalKb > 0 ? root.sizeText(SysInfo.memTotalKb - SysInfo.memAvailKb) + " used" : ""
        progress: SysInfo.memPct
        status: SysInfo.memPct > 0.9 ? 2 : (SysInfo.memPct > 0.75 ? 1 : 0)
    }

    Vital {
        id: _disk
        live: root.active
        glyph: "󰋊"
        label: "Disk"
        value: SysInfo.diskTotalKb > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
        sub: SysInfo.diskTotalKb > 0 && SysInfo.diskAvailKb > 0 ? root.sizeText(SysInfo.diskAvailKb) + " free" : ""
        progress: SysInfo.diskPct
        status: SysInfo.diskPct > 0.9 ? 2 : (SysInfo.diskPct > 0.75 ? 1 : 0)
    }

    Vital {
        id: _battery
        live: root.active
        visible: Battery.available
        glyph: Battery.icon
        label: "Battery"
        value: Battery.available ? Battery.label : "—"
        sub: root.batteryDetail()
        progress: Battery.available ? Math.min(Battery.pct / 100, 1.0) : 0
        status: Battery.critical ? 2 : (Battery.low ? 1 : 0)
        pulse: Battery.alertPulse
    }
}
