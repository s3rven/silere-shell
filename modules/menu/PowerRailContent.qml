pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    required property bool active

    implicitHeight: _body.implicitHeight
    enabled: active
    focus: active

    readonly property bool _statusVisible: PowerProfiles.available || Battery.available
    readonly property string _batterySource: !Battery.available ? ""
        : Battery.critical ? "Critical"
        : Battery.low ? "Low"
        : Battery.full ? "Full"
        : Battery.charging ? "AC"
        : "Battery"
    readonly property string _batteryValue: Battery.label
    readonly property string _profileValue: PowerProfiles.profile !== ""
        ? PowerProfiles.label + (PowerProfiles.degraded ? " · throttled" : "")
        : PowerProfiles.syncing ? "..."
        : ""

    onActiveChanged: {
        if (active) {
            if (PowerProfiles.available) PowerProfiles.refresh()
        } else {
            _powReb.disarm()
            _powOff.disarm()
        }
    }

    function _runAction(command, title: string): void {
        MenuState.close()
        SystemTools.runOrNotify(command, title)
    }

    Column {
        id: _body
        width: parent.width
        spacing: 8

        Column {
            width: parent.width
            spacing: 2
            visible: root._statusVisible

            PowerRailRow {
                id: _powMode
                visible: PowerProfiles.available
                width: parent.width
                label: "Mode"
                value: root._profileValue
                glyph: PowerProfiles.glyph
                enabled: PowerProfiles.available && PowerProfiles.profile !== ""
                onTriggered: PowerProfiles.cycle()
            }

            PowerRailRow {
                visible: Battery.available
                width: parent.width
                interactive: false
                label: root._batterySource
                value: root._batteryValue
                glyph: Battery.icon
                tintedGlyph: true
                dangerous: Battery.critical
                accentColor: Battery.iconColor
            }
        }

        Column {
            width: parent.width
            spacing: 2

            Item {
                width: parent.width
                height: 20

                ShellText {
                    id: _actionsHdr
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: "Power"
                    color: Theme.withAlpha(Theme.menuTextMuted, 0.90)
                    font.pixelSize: Settings.fontMicro
                    font.letterSpacing: 0.5
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                Hairline {
                    anchors.left: _actionsHdr.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: _actionsHdr.verticalCenter
                    color: Theme.menuDivider
                }
            }

            PowerRailRow {
                id: _powLock
                width: parent.width
                label: "Lock"
                glyph: "󰍁"
                enabled: SystemTools.commandAvailable(Settings.lockCommand)
                onTriggered: root._runAction(Settings.lockCommand, "Lock failed")
            }

            PowerRailRow {
                id: _powSusp
                width: parent.width
                label: "Sleep"
                glyph: "󰒲"
                enabled: SystemTools.commandAvailable(Settings.suspendCommand)
                onTriggered: root._runAction(Settings.suspendCommand, "Suspend failed")
            }

            PowerRailRow {
                id: _powReb
                width: parent.width
                label: "Reboot"
                glyph: "󰑐"
                enabled: SystemTools.commandAvailable(Settings.rebootCommand)
                confirm: true
                dangerous: true
                onArmedChanged: if (armed) _powOff.disarm()
                onTriggered: root._runAction(Settings.rebootCommand, "Reboot failed")
            }

            PowerRailRow {
                id: _powOff
                width: parent.width
                label: "Power off"
                glyph: "󰐥"
                enabled: SystemTools.commandAvailable(Settings.poweroffCommand)
                confirm: true
                dangerous: true
                onArmedChanged: if (armed) _powReb.disarm()
                onTriggered: root._runAction(Settings.poweroffCommand, "Shut down failed")
            }
        }
    }
}
