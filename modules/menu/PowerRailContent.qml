pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"

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
    readonly property string _batteryValue: Battery.label.length > 0 ? Battery.label : ""
    readonly property string _profileValue: PowerProfiles.profile !== "" ? PowerProfiles.label
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

    function _firstAction() {
        if (_powLock.enabled) return _powLock
        if (_powSusp.enabled) return _powSusp
        if (_powReb.enabled)  return _powReb
        if (_powOff.enabled)  return _powOff
        return null
    }

    function _lastAction() {
        if (_powOff.enabled)  return _powOff
        if (_powReb.enabled)  return _powReb
        if (_powSusp.enabled) return _powSusp
        if (_powLock.enabled) return _powLock
        return null
    }

    function _navRows() {
        const rows = []
        if (_powMode.visible && _powMode.enabled) rows.push(_powMode)
        if (_powLock.enabled) rows.push(_powLock)
        if (_powSusp.enabled) rows.push(_powSusp)
        if (_powReb.enabled)  rows.push(_powReb)
        if (_powOff.enabled)  rows.push(_powOff)
        return rows
    }

    function _rowAfter(row, dir: int) {
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

    function commandAvailable(command): bool {
        if (!command || command.length === 0) return false
        const tool = String(command[0])
        if (tool === "hyprlock")  return SystemTools.hasHyprlock
        if (tool === "systemctl") return SystemTools.hasSystemctl
        if (tool === "loginctl")  return SystemTools.hasLoginctl
        return true
    }

    function _shq(s): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function runPower(command, failTitle): void {
        if (!command || command.length === 0) return
        if (!SystemTools.hasNotifySend) {
            Quickshell.execDetached(command)
            return
        }
        const note = "notify-send --urgency=critical --app-name=silere-shell " +
            _shq(failTitle) + " " + _shq("It may require authorization or be blocked by a running task.")
        const argv = ["bash", "-c", '"$@" || ' + note, "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        Quickshell.execDetached(argv)
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
                glyph: PowerProfiles.glyph.length > 0 ? PowerProfiles.glyph : "󰾅"
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

                Text {
                    id: _actionsHdr
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: "Power"
                    color: Theme.withAlpha(Theme.menuTextMuted, 0.90)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize - 3
                    font.letterSpacing: 0.5
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    renderType: Text.NativeRendering
                }
                Rectangle {
                    anchors.left: _actionsHdr.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: _actionsHdr.verticalCenter
                    height: 1
                    radius: 0.5
                    color: Theme.menuDivider
                }
            }

            PowerRailRow {
                id: _powLock
                width: parent.width
                label: "Lock"
                glyph: "󰍁"
                enabled: root.commandAvailable(Settings.lockCommand)
                KeyNavigation.up: root._rowAfter(_powLock, -1)
                KeyNavigation.down: root._rowAfter(_powLock, 1)
                onTriggered: {
                    MenuState.close()
                    Quickshell.execDetached(Settings.lockCommand)
                }
            }

            PowerRailRow {
                id: _powSusp
                width: parent.width
                label: "Sleep"
                glyph: "󰒲"
                enabled: root.commandAvailable(Settings.suspendCommand)
                KeyNavigation.up: root._rowAfter(_powSusp, -1)
                KeyNavigation.down: root._rowAfter(_powSusp, 1)
                onTriggered: {
                    MenuState.close()
                    root.runPower(Settings.suspendCommand, "Suspend failed")
                }
            }

            PowerRailRow {
                id: _powReb
                width: parent.width
                label: "Reboot"
                glyph: "󰑐"
                enabled: root.commandAvailable(Settings.rebootCommand)
                confirm: true
                dangerous: true
                KeyNavigation.up: root._rowAfter(_powReb, -1)
                KeyNavigation.down: root._rowAfter(_powReb, 1)
                onArmedChanged: if (armed) _powOff.disarm()
                onTriggered: {
                    MenuState.close()
                    root.runPower(Settings.rebootCommand, "Reboot failed")
                }
            }

            PowerRailRow {
                id: _powOff
                width: parent.width
                label: "Power off"
                glyph: "󰐥"
                enabled: root.commandAvailable(Settings.poweroffCommand)
                confirm: true
                dangerous: true
                KeyNavigation.up: root._rowAfter(_powOff, -1)
                KeyNavigation.down: root._rowAfter(_powOff, 1)
                onArmedChanged: if (armed) _powReb.disarm()
                onTriggered: {
                    MenuState.close()
                    root.runPower(Settings.poweroffCommand, "Shut down failed")
                }
            }
        }
    }
}
