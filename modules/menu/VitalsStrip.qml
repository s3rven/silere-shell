import QtQuick
import "../../config"
import "../../services"

// static layout + in-place bindings: no Repeater model or Canvas that would rebuild every 60fps alert poll
Rectangle {
    id: root

    property bool active: true
    readonly property int _pad: 7

    width: parent ? parent.width : 0
    implicitHeight: _grid.implicitHeight + 2 * _pad
    height: implicitHeight
    radius: Theme.radiusCard
    antialiasing: true
    color: Theme.menuCard
    border.width: 1
    border.color: Theme.menuCardBorder

    // KPI column: value stacked over its label, gauge underneath — no dead space between label and value
    component Vital: Item {
        id: tile

        property string glyph: ""
        property string label: ""
        property string value: ""
        // secondary reading (CPU temp) rendered smaller and muted beside the value
        property string sub: ""
        property real   progress: 0
        // 0 ok, 1 warning, 2 critical
        property int    status: 0
        property real   pulse: 0
        property bool   live: true
        property bool   divider: true
        // sides facing a divider get extra air; card-edge sides stay on the page rows' 14px inset
        readonly property int padL: divider ? 18 : 14
        property int          padR: 18

        readonly property color tint: status === 2 ? Theme.error
                                    : status === 1 ? Theme.warning
                                    : Theme.menuTextMuted

        height: 70

        readonly property real _p: Math.max(0, Math.min(1, progress))
        property real _disp: _p
        Behavior on _disp {
            enabled: tile.live && !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.ms(450); easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: tile.divider
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(parent.height * 0.52)
            color: Theme.withAlpha(Theme.subtext, 0.10)
        }

        // Alert wash only appears for actual warning states; borderless — the tinted bar and value carry the state.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            antialiasing: true
            visible: tile.pulse > 0.001
            color: Theme.withAlpha(tile.tint, tile.pulse * 0.08)
        }

        Row {
            id: _labelRow
            anchors.left: parent.left
            anchors.leftMargin: tile.padL
            y: 11
            spacing: 4

            Text {
                id: _gl
                text: tile.glyph
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.menuTextMuted, tile.tint, 0.36 + tile.pulse * 0.38)
                    : Theme.withAlpha(Theme.menuTextMuted, 0.66)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 3
                renderType: Text.NativeRendering
            }
            Text {
                anchors.baseline: _gl.baseline
                text: tile.label
                color: Theme.withAlpha(Theme.menuTextMuted, 0.62)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 3
                font.letterSpacing: 0.4
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
            }
        }

        Row {
            id: _valueRow
            anchors.left: parent.left
            anchors.leftMargin: tile.padL
            anchors.top: _labelRow.bottom
            anchors.topMargin: 3
            spacing: 4

            Text {
                id: _val
                text: tile.value
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.text, tile.tint, tile.pulse * 0.5)
                    : tile.status > 0
                        ? Theme.mix(Theme.text, tile.tint, 0.45)
                        : Theme.withAlpha(Theme.text, 0.92)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
            }
            Text {
                visible: tile.sub !== ""
                anchors.baseline: _val.baseline
                text: tile.sub
                color: tile.pulse > 0.001
                    ? Theme.mix(Theme.menuTextMuted, tile.tint, tile.pulse * 0.6)
                    : Theme.withAlpha(Theme.menuTextMuted, 0.85)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
            }
        }

        // Baseline gauge: slider-language accent fill at rest, status-coloured for warning cells.
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
                Behavior on color { ColorAnimation { duration: Motion.color } }
            }
        }
    }

    // no horizontal inset: each column carries the page rows' own 14px text inset
    Row {
        id: _grid
        y: root._pad
        width: parent.width
        readonly property int  cells: Battery.available ? 4 : 3
        readonly property real cellW: width / cells

        Vital {
            width: _grid.cellW
            live: root.active
            divider: false
            glyph: "󰔏"
            label: "CPU"
            value: Math.round(SysInfo.cpuPct * 100) + "%"
            sub: CpuTemp.available ? Math.round(CpuTemp.temp) + "°" : ""
            progress: SysInfo.cpuPct
            status: CpuTemp.critical ? 2 : (CpuTemp.hot ? 1 : 0)
            pulse: CpuTemp.alertPulse
        }

        Vital {
            width: _grid.cellW
            live: root.active
            glyph: "󰘚"
            label: "Mem"
            value: SysInfo.memTotalKb > 0 ? Math.round(SysInfo.memPct * 100) + "%" : "—"
            progress: SysInfo.memPct
        }

        Vital {
            width: _grid.cellW
            live: root.active
            padR: Battery.available ? 18 : 14
            glyph: "󰋊"
            label: "Disk"
            value: SysInfo.diskPct > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
            progress: SysInfo.diskPct
            status: SysInfo.diskPct > 0.9 ? 2 : (SysInfo.diskPct > 0.75 ? 1 : 0)
        }

        Vital {
            width: _grid.cellW
            live: root.active
            visible: Battery.available
            padR: 14
            glyph: Battery.icon
            label: "Batt"
            value: Battery.available ? Battery.label : "—"
            progress: Battery.available ? Math.min(Battery.pct / 100, 1.0) : 0
            status: Battery.critical ? 2 : (Battery.low ? 1 : 0)
            pulse: Battery.alertPulse
        }
    }
}
