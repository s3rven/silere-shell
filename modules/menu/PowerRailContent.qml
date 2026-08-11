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
    activeFocusOnTab: active

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
            Qt.callLater(function() {
                if (root.active) root.forceActiveFocus()
            })
        } else {
            _powReb.disarm()
            _powOff.disarm()
        }
    }

    function _firstAction(): var {
        if (_powLock.enabled) return _powLock
        if (_powSusp.enabled) return _powSusp
        if (_powReb.enabled)  return _powReb
        if (_powOff.enabled)  return _powOff
        return null
    }

    function _lastAction(): var {
        if (_powOff.enabled)  return _powOff
        if (_powReb.enabled)  return _powReb
        if (_powSusp.enabled) return _powSusp
        if (_powLock.enabled) return _powLock
        return null
    }

    function _navRows(): var {
        const rows = []
        if (_powMode.visible && _powMode.enabled) rows.push(_powMode)
        if (_powLock.enabled) rows.push(_powLock)
        if (_powSusp.enabled) rows.push(_powSusp)
        if (_powReb.enabled)  rows.push(_powReb)
        if (_powOff.enabled)  rows.push(_powOff)
        return rows
    }

    function _rowAfter(row, dir: int): var {
        const rows = _navRows()
        if (rows.length === 0) return row
        const idx = rows.indexOf(row)
        if (idx < 0) return dir > 0 ? rows[0] : rows[rows.length - 1]
        return rows[(idx + dir + rows.length) % rows.length]
    }

    function focusFirstAction(): void {
        const item = _firstAction()
        if (item) item.forceActiveFocus()
    }

    function focusLastAction(): void {
        const item = _lastAction()
        if (item) item.forceActiveFocus()
    }

    Keys.onDownPressed: event => { root.focusFirstAction(); event.accepted = true }
    Keys.onRightPressed: event => { root.focusFirstAction(); event.accepted = true }
    Keys.onUpPressed: event => { root.focusLastAction(); event.accepted = true }
    Keys.onLeftPressed: event => { root.focusLastAction(); event.accepted = true }

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
                KeyNavigation.down: root._rowAfter(_powMode, 1)
                KeyNavigation.up: root._rowAfter(_powMode, -1)
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
                KeyNavigation.up: root._rowAfter(_powLock, -1)
                KeyNavigation.down: root._rowAfter(_powLock, 1)
                onTriggered: {
                    MenuState.close()
                    SystemTools.runOrNotify(Settings.lockCommand, "Lock failed")
                }
            }

            PowerRailRow {
                id: _powSusp
                width: parent.width
                label: "Sleep"
                glyph: "󰒲"
                enabled: SystemTools.commandAvailable(Settings.suspendCommand)
                KeyNavigation.up: root._rowAfter(_powSusp, -1)
                KeyNavigation.down: root._rowAfter(_powSusp, 1)
                onTriggered: {
                    MenuState.close()
                    SystemTools.runOrNotify(Settings.suspendCommand, "Suspend failed")
                }
            }

            PowerRailRow {
                id: _powReb
                width: parent.width
                label: "Reboot"
                glyph: "󰑐"
                enabled: SystemTools.commandAvailable(Settings.rebootCommand)
                confirm: true
                dangerous: true
                KeyNavigation.up: root._rowAfter(_powReb, -1)
                KeyNavigation.down: root._rowAfter(_powReb, 1)
                onArmedChanged: if (armed) _powOff.disarm()
                onTriggered: {
                    MenuState.close()
                    SystemTools.runOrNotify(Settings.rebootCommand, "Reboot failed")
                }
            }

            PowerRailRow {
                id: _powOff
                width: parent.width
                label: "Power off"
                glyph: "󰐥"
                enabled: SystemTools.commandAvailable(Settings.poweroffCommand)
                confirm: true
                dangerous: true
                KeyNavigation.up: root._rowAfter(_powOff, -1)
                KeyNavigation.down: root._rowAfter(_powOff, 1)
                onArmedChanged: if (armed) _powReb.disarm()
                onTriggered: {
                    MenuState.close()
                    SystemTools.runOrNotify(Settings.poweroffCommand, "Shut down failed")
                }
            }
        }
    }
}
