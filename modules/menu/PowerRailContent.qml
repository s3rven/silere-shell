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
        : Battery.onAc ? "AC"
        : "Battery"
    readonly property string _batteryValue: Battery.label
    // "Performance · throttled" overflows the rail at every size; degraded rides the row tint and the Now page says the word
    readonly property string _profileValue: PowerProfiles.changing ? "Changing…"
        : PowerProfiles.lastError.length > 0 ? "Failed"
        : PowerProfiles.profile !== "" ? PowerProfiles.label
        : "Unavailable"

    // the rail is built on each open with active already set, which runs no change handler
    Component.onCompleted: if (active) Session.refresh()
    onActiveChanged: {
        if (active) { Session.refresh(); return }
        _powOut.disarm()
        _powReb.disarm()
        _powOff.disarm()
    }

    function _runAction(command, title: string): void {
        MenuState.close()
        SystemAlerts.runOrNotify(command, title)
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
                visible: PowerProfiles.available
                width: parent.width
                label: root._profileValue
                glyph: PowerProfiles.glyph
                dangerous: PowerProfiles.degraded || PowerProfiles.lastError.length > 0
                enabled: PowerProfiles.available && PowerProfiles.profile !== ""
                    && !PowerProfiles.changing
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
                width: parent.width
                label: "Lock"
                glyph: "󰍁"
                enabled: SystemTools.commandAvailable(Settings.lockCommand)
                onTriggered: root._runAction(Settings.lockCommand, "Lock failed")
            }

            PowerRailRow {
                width: parent.width
                label: "Lock & sleep"
                glyph: "󰌾"
                value: Session.busy ? "Locking…" : ""
                enabled: Session.canLockSleep && !Session.busy
                onTriggered: { if (Session.lockAndSleep()) MenuState.close() }
            }

            PowerRailRow {
                width: parent.width
                label: "Sleep"
                glyph: "󰒲"
                enabled: SystemTools.commandAvailable(Settings.suspendCommand)
                onTriggered: root._runAction(Settings.suspendCommand, "Sleep failed")
            }

            PowerRailRow {
                width: parent.width
                visible: Session.canHibernate
                label: "Hibernate"
                glyph: "󰜗"
                enabled: SystemTools.commandAvailable(Settings.hibernateCommand)
                onTriggered: root._runAction(Settings.hibernateCommand, "Hibernate failed")
            }

            PowerRailRow {
                id: _powOut
                width: parent.width
                label: "Log out"
                glyph: "󰍃"
                enabled: SystemTools.commandAvailable(Settings.logoutCommand)
                confirm: true
                dangerous: true
                onArmedChanged: if (armed) { _powReb.disarm(); _powOff.disarm() }
                onTriggered: root._runAction(Settings.logoutCommand, "Log out failed")
            }

            PowerRailRow {
                id: _powReb
                width: parent.width
                label: "Reboot"
                glyph: "󰑐"
                value: Updates.restartNeeded ? "Needed" : ""
                enabled: SystemTools.commandAvailable(Settings.rebootCommand)
                confirm: true
                dangerous: true
                onArmedChanged: if (armed) { _powOut.disarm(); _powOff.disarm() }
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
                onArmedChanged: if (armed) { _powOut.disarm(); _powReb.disarm() }
                onTriggered: root._runAction(Settings.poweroffCommand, "Power off failed")
            }
        }
    }
}
