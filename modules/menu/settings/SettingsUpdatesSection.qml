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
    property bool _changesOpen: false
    property bool _recentOpen: false
    property bool _installArmed: false

    // commit and package entries scroll inside a capped list with no dividers, so they
    // track the text rather than the row grid every other settings row snaps to
    readonly property int _entryH: Math.max(22, Settings.capHeight + 8)

    function _disarmInstall(): void {
        root._installArmed = false
        _installConfirm.stop()
    }

    function _triggerShellAction(): void {
        if (!ShellUpdate.pending) {
            root._disarmInstall()
            ShellUpdate.check()
            return
        }
        if (!root._installArmed) {
            root._installArmed = true
            root._changesOpen = true
            _installConfirm.restart()
            return
        }
        root._disarmInstall()
        ShellUpdate.apply()
    }

    Timer {
        id: _installConfirm
        interval: 10000
        onTriggered: root._installArmed = false
    }

    // git only runs when the row is opened, never on the page building
    function _toggleRecent(): void {
        root._recentOpen = !root._recentOpen
        if (root._recentOpen && !ShellUpdate.recentReady) ShellUpdate.refreshRecent()
    }
    readonly property bool _changesAvailable: ShellUpdate.pending
        && ShellUpdate.pendingCommits.length > 0
    readonly property bool _packagesAvailable: Updates.count > 0
        && !Updates.lastFailed && Updates.packages.length > 0

    on_ChangesAvailableChanged: if (!_changesAvailable) {
        _changesOpen = false
        _disarmInstall()
    }
    on_PackagesAvailableChanged: if (!_packagesAvailable) _listOpen = false

    Connections {
        target: MenuState
        function onOpenChanged() { if (!MenuState.open) root._disarmInstall() }
    }
    Connections {
        target: ShellUpdate
        function onCountChanged() { root._disarmInstall() }
        function onTargetTagChanged() { root._disarmInstall() }
        function onTargetVerifiedChanged() { root._disarmInstall() }
        function onCheckingChanged() { if (ShellUpdate.checking) root._disarmInstall() }
        function onApplyingChanged() { if (ShellUpdate.applying) root._disarmInstall() }
    }

    width: parent ? parent.width : 0
    spacing: 0

    CollapsibleSection {
        expanded: !ShellUpdate.packaged

        SectionLabel { label: "SILERE SHELL"; first: true }
        SettingsCard {
            UpdateStatusCard {
                animationActive: root.animationActive
                glyph: ShellUpdate.checking || ShellUpdate.applying ? "󰓦"
                    : ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0 ? "󰀦"
                    : ShellUpdate.pending ? "󰚰" : "󰄬"
                title: "Silere Shell"
                status: ShellUpdate.statusDetail
                meta: ShellUpdate.versionLabel
                detail: ShellUpdate.lastApplyError.length > 0 ? ShellUpdate.lastApplyError
                    : ShellUpdate.lastCheckError.length > 0 ? ShellUpdate.lastCheckError
                    : ShellUpdate.pending && ShellUpdate.blockedReason.length > 0
                        ? ShellUpdate.blockedReason + " — installing will not run until that is resolved"
                    : root._installArmed
                        ? ShellUpdate.verificationDetail + " · confirm installation within 10 seconds"
                    : ShellUpdate.pending ? ShellUpdate.verificationDetail
                    : ShellUpdate.versionDetail
                detailError: ShellUpdate.lastApplyError.length > 0 || ShellUpdate.lastCheckError.length > 0
                    || (ShellUpdate.pending && ShellUpdate.blockedReason.length > 0)
                statusColor: ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0
                    ? Theme.warning : ShellUpdate.checking || ShellUpdate.applying || ShellUpdate.pending
                        ? Theme.accent : Theme.success
                busy: ShellUpdate.checking || ShellUpdate.applying

                primaryLabel: ShellUpdate.applying ? "Installing…"
                    : root._installArmed ? "Confirm" : ShellUpdate.pending ? "Install" : "Check"
                primaryGlyph: root._installArmed ? "󰌾" : ShellUpdate.pending ? "󰅢" : "󰓦"
                primaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
                    && (!ShellUpdate.pending || (ShellUpdate.targetVerified
                        && ShellUpdate.blockedReason.length === 0))
                primaryEmphasis: ShellUpdate.pending
                primaryColor: root._installArmed ? Theme.warning : Theme.accent
                onPrimaryTriggered: root._triggerShellAction()

                secondaryShown: ShellUpdate.pending && !ShellUpdate.applying
                secondaryGlyph: "󰑐"
                secondaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
                onSecondaryTriggered: ShellUpdate.check()
            }

            ControlRow {
                glyph: "󰜘"
                title: "Pending changes"
                status: ShellUpdate.targetLabel.length > 0
                    ? "Moves to " + ShellUpdate.targetLabel : ""
                valueText: ShellUpdate.pendingCommits.length < ShellUpdate.count
                    ? ShellUpdate.pendingCommits.length + " of " + ShellUpdate.count
                    : String(ShellUpdate.count)
                visible: root._changesAvailable
                expandable: true
                chevronTabFocusable: false
                expanded: root._changesOpen && root._changesAvailable
                onExpandToggled: root._changesOpen = !root._changesOpen
                onActivated: root._changesOpen = !root._changesOpen
            }
            CollapsibleSection {
                expanded: root._changesOpen && root._changesAvailable
                Item {
                    width: parent ? parent.width : 0
                    height: Math.min(_commits.contentHeight, 240)

                    ShellListView {
                        id: _commits
                        anchors.fill: parent
                        interactive: contentHeight > height
                        spacing: 0
                        model: root._changesOpen && root._changesAvailable
                            ? ShellUpdate.pendingCommits : []

                        Accessible.role: Accessible.List
                        Accessible.name: "Pending shell changes"

                        delegate: Item {
                            id: _commit
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: root._entryH
                            Accessible.role: Accessible.ListItem
                            Accessible.name: _commit.modelData.subject
                                + ", " + _commit.modelData.hash
                            ShellText {
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.right: _hash.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: _commit.modelData.subject
                                elide: Text.ElideRight
                                color: Theme.withAlpha(Theme.text, 0.80)
                                font.pixelSize: Settings.fontLabel
                            }
                            ShellText {
                                id: _hash
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: _commit.modelData.hash
                                color: Theme.withAlpha(Theme.subtext, 0.55)
                                font.pixelSize: Settings.fontCaption
                            }
                        }
                    }

                    ListEdgeLines {
                        anchors.fill: parent
                        list: _commits
                    }
                }
            }

            ControlRow {
                glyph: "󰄉"
                title: "Recent changes"
                status: ShellUpdate.recentBusy ? "Reading history" : ""
                valueText: ShellUpdate.recentReady
                    ? String(ShellUpdate.recentCommits.length) : ""
                expandable: true
                chevronTabFocusable: false
                expanded: root._recentOpen
                onExpandToggled: root._toggleRecent()
                onActivated: root._toggleRecent()
            }
            CollapsibleSection {
                expanded: root._recentOpen
                Item {
                    width: parent ? parent.width : 0
                    height: Math.min(_recent.contentHeight, 240)

                    ShellListView {
                        id: _recent
                        anchors.fill: parent
                        interactive: contentHeight > height
                        spacing: 0
                        model: root._recentOpen ? ShellUpdate.recentCommits : []

                        Accessible.role: Accessible.List
                        Accessible.name: "Recent shell changes"

                        delegate: Item {
                            id: _rc
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: root._entryH
                            Accessible.role: Accessible.ListItem
                            Accessible.name: _rc.modelData.subject + ", " + _rc.modelData.hash
                            ShellText {
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.right: _rcHash.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: _rc.modelData.subject
                                elide: Text.ElideRight
                                color: Theme.withAlpha(Theme.text, 0.80)
                                font.pixelSize: Settings.fontLabel
                            }
                            ShellText {
                                id: _rcHash
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: _rc.modelData.hash
                                color: Theme.withAlpha(Theme.subtext, 0.55)
                                font.pixelSize: Settings.fontCaption
                            }
                        }
                    }

                    ListEdgeLines {
                        anchors.fill: parent
                        list: _recent
                    }
                }
            }

            ToggleRow {
                glyph: "󰥔"; label: "Daily shell update check"
                description: ShellUpdate.timerError.length > 0
                    ? ShellUpdate.timerError : ShellUpdate.nextCheckText
                checked: ShellUpdate.timerEnabled
                enabled: !ShellUpdate.timerBusy
                available: ShellUpdate.timerSupported
                dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
                onToggled: nextChecked => ShellUpdate.setTimerEnabled(nextChecked)
            }
        }
    }

    SectionLabel { label: "SYSTEM PACKAGES"; first: ShellUpdate.packaged }
    SettingsCard {
        UpdateStatusCard {
            animationActive: root.animationActive
            glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
            title: "System packages"
            status: Updates.statusText
            meta: Updates.managerLabel
            detail: Updates.lastFailed ? Updates.lastError
                : Updates.aurCount > 0
                    ? Updates.repoCount + " from repos, " + Updates.aurCount + " from the AUR"
                        + (Updates.lastCheckLabel.length > 0 ? " · " + Updates.lastCheckLabel : "")
                    : Updates.lastCheckLabel
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
            visible: root._packagesAvailable
            expandable: true
            chevronTabFocusable: false
            expanded: root._listOpen && root._packagesAvailable
            onExpandToggled: root._listOpen = !root._listOpen
            onActivated: root._listOpen = !root._listOpen
        }
        CollapsibleSection {
            expanded: root._listOpen && root._packagesAvailable
            Item {
                width: parent ? parent.width : 0
                height: Math.min(_packages.contentHeight, 240)

                ShellListView {
                    id: _packages
                    anchors.fill: parent
                    interactive: contentHeight > height
                    spacing: 0
                    model: root._listOpen && root._packagesAvailable
                        ? Updates.packages : []

                    Accessible.role: Accessible.List
                    Accessible.name: "Pending system packages"

                    delegate: Item {
                        id: _pkg
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: root._entryH
                        Accessible.role: Accessible.ListItem
                        Accessible.name: _pkg.modelData.name + ", version "
                            + _pkg.modelData.to
                            + (_pkg.modelData.from.length > 0
                                ? ", from " + _pkg.modelData.from : "")
                            + (_pkg.modelData.aur ? ", AUR" : "")
                        ShellText {
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: _ver.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.name
                            elide: Text.ElideRight
                            color: Theme.withAlpha(Theme.text, 0.80)
                            font.pixelSize: Settings.fontLabel
                        }
                        ShellText {
                            id: _ver
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.to + (_pkg.modelData.aur ? "  AUR" : "")
                            color: Theme.withAlpha(Theme.subtext,
                                _pkg.modelData.aur ? 0.75 : 0.55)
                            font.pixelSize: Settings.fontCaption
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
            description: "Show pending count in bar"
            key: "updatesWidget"
            available: !SystemTools.ready || Updates.supported
            dependsNote: "No package manager"
        }
        ToggleRow {
            visible: SystemTools.packageFamily === "pacman"
                && Updates.aurHelperAvailable
            glyph: "󰮯"; label: "Include AUR packages"
            description: "Query "
                + (SystemTools.hasParu ? "paru" : "yay")
                + " for foreign package updates"
            key: "updatesIncludeAur"
        }
        HintText { text: "Checks are read-only and never install updates." }
    }
}
