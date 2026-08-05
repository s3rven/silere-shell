pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Column {
    id: root

    property bool animationActive: true
    property bool _listOpen: false

    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        UpdateStatusCard {
            animationActive: root.animationActive
            glyph: ShellUpdate.checking || ShellUpdate.applying ? "󰓦"
                : ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0 ? "󰀦"
                : ShellUpdate.pending ? "󰚰" : "󰄬"
            title: "Silere Shell"
            status: ShellUpdate.statusText
            meta: ShellUpdate.currentVersion.length > 0 ? "#" + ShellUpdate.currentVersion : ""
            detail: ShellUpdate.lastApplyError.length > 0 ? ShellUpdate.lastApplyError
                : ShellUpdate.lastCheckError.length > 0 ? ShellUpdate.lastCheckError
                : ShellUpdate.pending ? ShellUpdate.summary : ""
            detailError: ShellUpdate.lastApplyError.length > 0 || ShellUpdate.lastCheckError.length > 0
            statusColor: ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0
                ? Theme.warning : ShellUpdate.checking || ShellUpdate.applying || ShellUpdate.pending
                    ? Theme.accent : Theme.success
            busy: ShellUpdate.checking || ShellUpdate.applying

            primaryLabel: ShellUpdate.pending || ShellUpdate.applying ? "Install" : "Check"
            primaryGlyph: ShellUpdate.pending ? "󰅢" : "󰓦"
            primaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
            primaryEmphasis: ShellUpdate.pending
            onPrimaryTriggered: {
                if (ShellUpdate.pending) ShellUpdate.apply()
                else ShellUpdate.check()
            }

            secondaryShown: ShellUpdate.pending && !ShellUpdate.applying
            secondaryGlyph: "󰑐"
            secondaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
            onSecondaryTriggered: ShellUpdate.check()
        }

        UpdateStatusCard {
            animationActive: root.animationActive
            glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
            title: "System packages"
            status: Updates.statusText
            meta: Updates.managerLabel
            detail: Updates.lastFailed ? Updates.lastError
                : Updates.aurCount > 0
                    ? Updates.repoCount + " from repos, " + Updates.aurCount + " from the AUR"
                    : ""
            detailError: Updates.lastFailed
            statusColor: Updates.lastFailed ? Theme.warning
                : Updates.isChecking ? Theme.accent
                : Updates.enabled && Updates.ready && Updates.count === 0 ? Theme.success
                : Updates.count > 0 ? Theme.accent : Theme.subtext
            busy: Updates.isChecking

            primaryLabel: !SystemTools.ready ? "Detecting…"
                : !Updates.supported ? "Unavailable"
                : !ShellSettings.updatesWidget ? "Off"
                : Updates.isChecking ? "Checking…" : "Check"
            primaryGlyph: "󰓦"
            primaryEnabled: SystemTools.ready && Updates.supported
                && ShellSettings.updatesWidget && !Updates.isChecking
            onPrimaryTriggered: Updates.refresh()
        }
        ControlRow {
            glyph: "󰏗"
            title: "Pending packages"
            valueText: Updates.packages.length < Updates.count
                ? Updates.packages.length + " of " + Updates.count : String(Updates.count)
            visible: Updates.count > 0 && !Updates.lastFailed && Updates.packages.length > 0
            expandable: true
            expanded: root._listOpen
            onExpandToggled: root._listOpen = !root._listOpen
            onActivated: root._listOpen = !root._listOpen
        }
        CollapsibleSection {
            expanded: root._listOpen && Updates.count > 0 && !Updates.lastFailed
            Item {
                width: parent ? parent.width : 0
                height: Math.min(_packages.contentHeight, 240)

                ListView {
                    id: _packages
                    anchors.fill: parent
                    clip: true
                    interactive: contentHeight > height
                    boundsMovement: Flickable.StopAtBounds
                    flickDeceleration: 1800
                    maximumFlickVelocity: 2200
                    spacing: 0
                    model: root._listOpen ? Updates.packages : []

                    delegate: Item {
                        id: _pkg
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: Math.max(22, Settings.capHeight + 8)
                        ShellText {
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: _ver.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.name
                            elide: Text.ElideRight
                            color: Theme.withAlpha(Theme.text, 0.80)
                            font.pixelSize: Settings.fontSize - 1
                        }
                        ShellText {
                            id: _ver
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.to + (_pkg.modelData.aur ? "  AUR" : "")
                            color: Theme.withAlpha(Theme.subtext,
                                _pkg.modelData.aur ? 0.75 : 0.55)
                            font.pixelSize: Settings.fontSize - 2
                        }
                    }
                }

                ListEdgeLines {
                    anchors.fill: parent
                    list: _packages
                }
            }
        }
        ToggleRow {
            glyph: "󰚰"; label: "Track package updates"
            description: "Pending-update badge in the bar"
            checked: ShellSettings.updatesWidget
            onToggled: nextChecked => ShellSettings.updatesWidget = nextChecked
            available: !SystemTools.ready || Updates.supported
            dependsNote: "No package manager"
        }
        ToggleRow {
            glyph: "󰥔"; label: "Daily update check"
            checked: ShellUpdate.timerEnabled
            enabled: !ShellUpdate.timerBusy
            available: ShellUpdate.timerSupported
            dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
            onToggled: nextChecked => ShellUpdate.setTimerEnabled(nextChecked)
        }
        HintText { text: "Checks never install anything on their own." }
    }
}
