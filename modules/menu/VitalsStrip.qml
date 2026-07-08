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
    clip: true
    color: Theme.menuCard
    border.width: 1
    border.color: Theme.menuCardBorder

    component Vital: Item {
        id: tile

        property string glyph: ""
        property string label: ""
        property string value: ""
        property real   progress: 0
        property color  tint: Theme.accent
        property real   pulse: 0
        property bool   live: true

        height: 46

        readonly property real _p: Math.max(0, Math.min(1, progress))
        property real _disp: _p
        Behavior on _disp {
            enabled: tile.live && !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.ms(450); easing.type: Easing.OutCubic }
        }

        // Alert wash only appears for actual warning states; normal readings stay neutral.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            antialiasing: true
            visible: tile.pulse > 0.001
            color: Theme.withAlpha(tile.tint, tile.pulse * 0.05)
            border.width: 1
            border.color: Theme.withAlpha(tile.tint, tile.pulse * 0.26)
        }

        Text {
            id: _ic
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -5
            text: tile.glyph
            color: tile.pulse > 0.001
                ? Theme.mix(Theme.menuTextMuted, tile.tint, 0.36 + tile.pulse * 0.38)
                : Theme.withAlpha(Theme.menuTextMuted, 0.78)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType: Text.NativeRendering
        }

        Text {
            id: _val
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -5
            text: tile.value
            color: tile.pulse > 0.001
                ? Theme.mix(Theme.text, tile.tint, tile.pulse * 0.5)
                : Theme.withAlpha(Theme.text, 0.88)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 1
            font.weight: Font.DemiBold
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
        }

        Text {
            anchors.left: _ic.right
            anchors.leftMargin: 7
            anchors.right: _val.left
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -5
            text: tile.label
            color: Theme.withAlpha(Theme.menuTextMuted, 0.82)
            font.family: Settings.font
            font.pixelSize: Math.max(11, Settings.fontSize)
            font.weight: Font.Medium
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        // Baseline gauge: neutral by default, status-coloured only for warning cells.
        Rectangle {
            anchors.left: parent.left;     anchors.leftMargin: 12
            anchors.right: parent.right;   anchors.rightMargin: 12
            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            height: 3
            radius: 1.5
            antialiasing: true
            color: Theme.menuTrack

            Rectangle {
                width: tile._disp <= 0 ? 0 : Math.max(parent.height, Math.round(parent.width * tile._disp))
                height: parent.height
                radius: parent.radius
                antialiasing: true
                color: tile.tint
            }
        }
    }

    Grid {
        id: _grid
        x: root._pad
        y: root._pad
        width: parent.width - 2 * root._pad
        columns: 2
        readonly property real cellW: width / 2

        Vital {
            width: _grid.cellW
            live: root.active
            glyph: "󰔏"
            label: "CPU"
            value: Math.round(SysInfo.cpuPct * 100) + "%" + (CpuTemp.available ? "  " + Math.round(CpuTemp.temp) + "°" : "")
            progress: SysInfo.cpuPct
            tint: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.menuTextMuted)
            pulse: CpuTemp.alertPulse
        }

        Vital {
            width: _grid.cellW
            live: root.active
            glyph: "󰘚"
            label: "Mem"
            value: SysInfo.memTotalKb > 0 ? Math.round(SysInfo.memPct * 100) + "%" : "—"
            progress: SysInfo.memPct
            tint: Theme.menuTextMuted
        }

        Vital {
            width: _grid.cellW
            live: root.active
            glyph: "󰋊"
            label: "Disk"
            value: SysInfo.diskPct > 0 ? Math.round(SysInfo.diskPct * 100) + "%" : "—"
            progress: SysInfo.diskPct
            tint: SysInfo.diskPct > 0.9 ? Theme.error : (SysInfo.diskPct > 0.75 ? Theme.warning : Theme.menuTextMuted)
        }

        Vital {
            width: _grid.cellW
            live: root.active
            visible: Battery.available
            glyph: Battery.icon
            label: "Batt"
            value: Battery.available ? Battery.label : "—"
            progress: Battery.available ? Math.min(Battery.pct / 100, 1.0) : 0
            tint: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.menuTextMuted)
            pulse: Battery.alertPulse
        }
    }

    // faint divider cross: fixed to the cell grid so it lines up even when the battery cell is absent
    Rectangle {
        x: root.width / 2
        y: root._pad + 10
        width: 1
        height: root.height - 2 * (root._pad + 10)
        color: Theme.withAlpha(Theme.subtext, 0.10)
    }
    Rectangle {
        x: root._pad + 12
        y: root._pad + 46
        width: root.width - 2 * (root._pad + 12)
        height: 1
        color: Theme.withAlpha(Theme.subtext, 0.10)
    }
}
