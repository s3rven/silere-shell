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
    property bool batteryExpanded: false
    signal batteryActivated()
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
    readonly property int _rowH: Metrics.rowHeightFor(40)
    // one width for every bar, the narrowest any caption allows: a bar sized to its own row drew 50% shorter
    // on Battery than on CPU, and the column could not be read as one scale
    readonly property real _barW: Math.min(_cpu.barFit, _memory.barFit, _disk.barFit,
        _battery.visible ? _battery.barFit : Infinity)

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
        // 0, 0.5 or 1: the wave rests calm and stirs with load; coarse steps, as each change eases the whole path
        property real   activity: 0
        property bool   live: true
        // a reading that has a fuller view opens the system monitor
        property bool   openable: false
        property string actionDescription: "Opens the system monitor"
        property real   topRadius: 0
        signal activated()

        readonly property color tint: status === 2 ? Theme.error
                                    : status === 1 ? Theme.warning
                                    : Theme.menuTextMuted

        TextMetrics {
            id: _labelMetrics
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            font.weight: Font.DemiBold
            text: tile.label
        }
        TextMetrics {
            id: _detailMetrics
            font.family: Settings.font
            font.pixelSize: Settings.fontCaption
            font.weight: Font.Medium
            text: tile.sub
        }

        width: parent ? parent.width : 0
        height: _textCol.inline ? root._rowH : Metrics.rowHeightFor(48)
        implicitHeight: height
        Accessible.role: tile.openable ? Accessible.Button : Accessible.StaticText
        Accessible.name: tile.label + " " + tile.value
        Accessible.description: tile.openable && tile.sub.length > 0
            ? tile.sub + ". " + tile.actionDescription
            : tile.openable ? tile.actionDescription : tile.sub
        Accessible.focusable: tile.openable && root.active
        Accessible.onPressAction: if (tile.openable) tile.activated()
        KeyboardFocus { interactive: tile.openable && root.active; onActivated: tile.activated() }

        RowHoverBg {
            anchors.fill: parent
            topRadius: tile.topRadius
            active: tile.openable && _tileHover.hovered
            pressed: tile.openable && _tileTap.pressed
        }
        HoverHandler {
            id: _tileHover
            enabled: tile.openable && root.active
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: _tileTap
            enabled: tile.openable && root.active
            onTapped: tile.activated()
        }

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

        // the detail follows its label on one line, and drops under it only where large text leaves no room
        Item {
            id: _textCol
            anchors.left: _iconSlot.right
            anchors.leftMargin: 10
            anchors.right: _bar.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool inline: tile.sub.length === 0
                || Math.ceil(_labelMetrics.advanceWidth) + 8 + Math.ceil(_detailMetrics.advanceWidth) <= width
            height: inline || !_detailText.visible ? _labelText.height
                : _labelText.height + 1 + _detailText.height

            ShellText {
                id: _labelText
                width: Math.min(implicitWidth, parent.width)
                text: tile.label
                color: Theme.withAlpha(Theme.text, 0.85)
                font.pixelSize: Settings.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ShellText {
                id: _detailText
                visible: tile.sub.length > 0 && width > 12
                x: _textCol.inline ? _labelText.width + 8 : 0
                y: _textCol.inline ? _labelText.baselineOffset - baselineOffset : _labelText.height + 1
                width: Math.max(0, parent.width - x)
                text: tile.sub
                color: tile.status > 0 ? Theme.mix(Theme.menuTextDetail, tile.tint, 0.5)
                    : Theme.menuTextDetail
                font.pixelSize: Settings.fontCaption
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        // give the reading's caption room before sizing its progress bar. Rounding up the text and down the bar avoids fractional elision
        readonly property real barFit: Metrics.snap4Down(Math.max(48, Math.min(136, tile.width * 0.38,
            _val.x - 64 - Math.max(96, Math.ceil(_labelMetrics.advanceWidth + 8
                + _detailMetrics.advanceWidth) + 1))))

        WaveLine {
            id: _bar
            anchors.right: _val.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: root._barW
            height: implicitHeight
            value: tile._disp
            reveal: tile._grow
            thickness: 3
            amplitude: tile.status > 0 ? 2 : 0.9 + tile.activity * 1.1
            wavelength: tile.status > 0 ? 12 : 16
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

    function openMonitor(): void {
        if (Settings.systemMonitorCommand.length === 0) return
        SystemTools.runOrNotify(Settings.systemMonitorCommand, "System monitor failed to start")
        MenuState.close()
    }

    Vital {
        id: _cpu
        live: root.active
        openable: Settings.systemMonitorCommand.length > 0
        topRadius: Theme.radiusCard
        onActivated: root.openMonitor()
        // the bar's CPU glyph; the temperature it alerts on rides in the caption and tint
        glyph: "󰍛"
        label: "CPU"
        value: SysInfo.cpuReady ? Math.round(SysInfo.cpuPct * 100) + "%" : "—"
        sub: CpuTemp.available ? Math.round(CpuTemp.temp) + "°" : ""
        progress: SysInfo.cpuReady ? SysInfo.cpuPct : 0
        activity: !SysInfo.cpuReady ? 0 : SysInfo.cpuPct >= 0.7 ? 1 : SysInfo.cpuPct >= 0.3 ? 0.5 : 0
        status: CpuTemp.critical ? 2 : (CpuTemp.hot || (SysInfo.cpuReady && SysInfo.cpuHigh) ? 1 : 0)
        pulse: CpuTemp.alertPulse
    }

    Vital {
        id: _memory
        live: root.active
        openable: Settings.systemMonitorCommand.length > 0
        onActivated: root.openMonitor()
        glyph: "󰘚"
        label: "Memory"
        value: SysInfo.memTotalKb > 0 ? Math.round(SysInfo.memPct * 100) + "%" : "—"
        // swap only joins the line while memory is actually stalling work, so a healthy machine stays quiet
        sub: SysInfo.memTotalKb > 0
            ? root.sizeText(SysInfo.memTotalKb - SysInfo.memAvailKb) + " used"
                + (SysInfo.swapActive ? " · " + root.sizeText(SysInfo.swapUsedKb) + " swap" : "")
            : ""
        progress: SysInfo.memPct
        status: SysInfo.memLevel
    }

    Vital {
        id: _disk
        live: root.active
        glyph: "󰋊"
        label: "Disk"
        value: SysInfo.diskTotalKb > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
        // a full disk is when the caption matters most, so it says so rather than going blank
        sub: SysInfo.diskTotalKb <= 0 ? "" : SysInfo.diskAvailKb > 0 ? root.sizeText(SysInfo.diskAvailKb) + " free" : "Full"
        progress: SysInfo.diskPct
        status: SysInfo.diskLevel
    }

    InlinePicker { id: _batteryAbove; mirror: _batteryPicker }

    Vital {
        id: _battery
        live: root.active
        visible: Battery.available
        openable: Battery.hasDetails
        actionDescription: "Shows battery details"
        onActivated: root.batteryActivated()
        glyph: Battery.icon
        label: "Battery"
        value: Battery.available ? Battery.label : "—"
        sub: root.batteryDetail()
        progress: Battery.available ? Math.min(Battery.pct / 100, 1.0) : 0
        status: Battery.critical ? 2 : (Battery.low ? 1 : 0)
        pulse: Battery.alertPulse
    }

    InlinePicker {
        id: _batteryPicker
        open: root.batteryExpanded && Battery.hasDetails
        content: Component { BatteryDetails {} }
    }
}
