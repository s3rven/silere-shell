pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root

    property bool animationActive: true
    property bool _listOpen: false
    property bool _changesOpen: false
    property bool _notesOpen: true
    property bool _recentOpen: false
    property bool _installArmed: false
    property real _installArmedAtMs: 0

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
            root._installArmedAtMs = Date.now()
            root._changesOpen = true
            _installConfirm.restart()
            return
        }
        if (Date.now() - root._installArmedAtMs < Metrics.confirmGuardMs) return
        root._disarmInstall()
        if (!ShellSettings.flushForUpdate()) {
            ShellUpdate.lastApplyError = "Settings could not be saved before the update"
            return
        }
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
    readonly property bool _releaseNotesAvailable: ShellUpdate.pending
        && ShellUpdate.releaseNotes.length > 0
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
        function onTargetTagChanged() {
            root._disarmInstall()
            root._notesOpen = true
        }
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
                    : ShellUpdate.checkError.length > 0 || ShellUpdate.lastApplyError.length > 0
                        || ShellUpdate.statusReadError.length > 0 ? "󰀦"
                    : ShellUpdate.development ? "󰊢"
                    : ShellUpdate.pending ? "󰚰"
                    : !ShellUpdate.statusReady || ShellUpdate.neverChecked ? "󰓦" : "󰄬"
                title: "Silere Shell"
                status: ShellUpdate.statusDetail
                meta: ShellUpdate.updateVersionLabel
                detail: ShellUpdate.lastApplyError.length > 0 ? ShellUpdate.lastApplyError
                    : ShellUpdate.checkError.length > 0
                        ? ShellUpdate.checkError + (ShellUpdate.checkErrorAge.length > 0
                            ? " · " + ShellUpdate.checkErrorAge : "")
                    : ShellUpdate.statusReadError.length > 0 ? ShellUpdate.statusReadError
                    : ShellUpdate.pending && ShellUpdate.blockedReason.length > 0
                        ? ShellUpdate.blockedReason + " — installing will not run until that is resolved"
                    : root._installArmed
                        ? ShellUpdate.verificationDetail + " · confirm installation within 10 seconds"
                    : ShellUpdate.pending ? ShellUpdate.verificationDetail
                    : ShellUpdate.versionDetail
                detailError: ShellUpdate.lastApplyError.length > 0 || ShellUpdate.checkError.length > 0
                    || ShellUpdate.statusReadError.length > 0
                    || (ShellUpdate.pending && ShellUpdate.blockedReason.length > 0)
                statusColor: ShellUpdate.checkError.length > 0 || ShellUpdate.lastApplyError.length > 0
                    || ShellUpdate.statusReadError.length > 0
                    ? Theme.warning : ShellUpdate.checking || ShellUpdate.applying || ShellUpdate.pending
                        ? Theme.accent : ShellUpdate.development
                            ? Theme.accent : !ShellUpdate.statusReady || ShellUpdate.neverChecked
                                ? Theme.subtext : Theme.success
                busy: ShellUpdate.checking || ShellUpdate.applying

                primaryLabel: ShellUpdate.applying ? "Installing…"
                    : ShellUpdate.development ? "Git managed"
                    : root._installArmed ? "Confirm" : ShellUpdate.pending ? "Install" : "Check"
                primaryGlyph: root._installArmed ? "󰌾" : ShellUpdate.pending ? "󰅢" : "󰓦"
                primaryEnabled: !ShellUpdate.development
                    && !ShellUpdate.checking && !ShellUpdate.applying
                    && (!ShellUpdate.pending || (ShellUpdate.targetVerified
                        && ShellUpdate.blockedReason.length === 0))
                primaryEmphasis: ShellUpdate.pending
                primaryColor: root._installArmed ? Theme.warning : Theme.accent
                onPrimaryTriggered: root._triggerShellAction()

                secondaryShown: ShellUpdate.pending && !ShellUpdate.development
                    && !ShellUpdate.applying
                secondaryGlyph: "󰑐"
                secondaryEnabled: !ShellUpdate.checking && !ShellUpdate.applying
                onSecondaryTriggered: ShellUpdate.check()
            }

            ControlRow {
                glyph: "󰋼"
                title: "Release notes"
                status: ShellUpdate.targetLabel.length > 0
                    ? ShellUpdate.targetLabel : ""
                valueText: String(ShellUpdate.releaseNotes.length)
                visible: root._releaseNotesAvailable
                expandable: true
                expanded: root._notesOpen && root._releaseNotesAvailable
                onExpandToggled: root._notesOpen = !root._notesOpen
                onActivated: root._notesOpen = !root._notesOpen
            }
            CollapsibleSection {
                expanded: root._notesOpen && root._releaseNotesAvailable
                EntryList {
                    model: root._notesOpen && root._releaseNotesAvailable
                        ? ShellUpdate.releaseNotes : []
                    textRole: "subject"
                    trailingRole: "category"
                }
            }

            ControlRow {
                glyph: "󰜘"
                title: "Technical details"
                status: "Commits in this release"
                valueText: ShellUpdate.pendingCommits.length < ShellUpdate.count
                    ? ShellUpdate.pendingCommits.length + " of " + ShellUpdate.count
                    : String(ShellUpdate.count)
                visible: root._changesAvailable
                expandable: true
                expanded: root._changesOpen && root._changesAvailable
                onExpandToggled: root._changesOpen = !root._changesOpen
                onActivated: root._changesOpen = !root._changesOpen
            }
            CollapsibleSection {
                expanded: root._changesOpen && root._changesAvailable
                EntryList {
                    model: root._changesOpen && root._changesAvailable
                        ? ShellUpdate.pendingCommits : []
                    textRole: "subject"
                    trailingRole: "hash"
                }
            }

            ControlRow {
                glyph: "󰄉"
                title: "Recent changes"
                status: ShellUpdate.recentBusy ? "Reading history" : ShellUpdate.recentError
                statusColor: ShellUpdate.recentError.length > 0 ? Theme.warning : "transparent"
                valueText: ShellUpdate.recentReady
                    ? String(ShellUpdate.recentCommits.length) : ""
                expandable: true
                expanded: root._recentOpen
                onExpandToggled: root._toggleRecent()
                onActivated: root._toggleRecent()
            }
            CollapsibleSection {
                expanded: root._recentOpen
                EntryList {
                    model: root._recentOpen ? ShellUpdate.recentCommits : []
                    textRole: "subject"
                    trailingRole: "hash"
                }
            }

            ToggleRow {
                glyph: "󰥔"; label: "Daily shell update check"
                description: ShellUpdate.timerError.length > 0
                    ? ShellUpdate.timerError : ShellUpdate.nextCheckText
                checked: ShellUpdate.timerEnabled
                enabled: !ShellUpdate.development && !ShellUpdate.timerBusy
                available: ShellUpdate.timerSupported && !ShellUpdate.development
                dependsNote: ShellUpdate.development ? "Git managed"
                    : ShellUpdate.timerBusy ? "Working"
                    : (!SystemTools.ready ? "Checking" : "No systemd")
                onToggled: nextChecked => ShellUpdate.setTimerEnabled(nextChecked)
            }
        }
    }

    CollapsibleSection {
        expanded: ShellUpdate.packaged

        SectionLabel { label: "SILERE SHELL"; first: true }
        SettingsCard {
            ControlRow {
                glyph: ShellUpdate.plainCopy ? "󰀦" : "󰄬"
                title: "Silere Shell"
                status: ShellUpdate.plainCopy ? "Not a Git checkout" : "Package-managed install"
                valueText: ShellUpdate.versionLabel
                statusColor: ShellUpdate.plainCopy ? Theme.warning : Theme.success
                passive: true
            }
            ControlRow {
                glyph: "󰏗"
                title: "Managed by"
                status: "Built-in self-update is disabled"
                valueText: ShellUpdate.plainCopy ? "nothing"
                    : SystemTools.packageFamily.length > 0 ? SystemTools.packageFamily : "packages"
                passive: true
            }
            HintText {
                text: ShellUpdate.plainCopy
                    ? "Nothing updates this copy. scripts/install.sh sets up one that can update itself."
                    : "Silere updates with the rest of the system. No second updater touches package-owned files."
            }
        }
    }

    SectionLabel { label: "SYSTEM PACKAGES" }
    SettingsCard {
        UpdateStatusCard {
            animationActive: root.animationActive
            glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
            title: "Packages"
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
            expanded: root._listOpen && root._packagesAvailable
            onExpandToggled: root._listOpen = !root._listOpen
            onActivated: root._listOpen = !root._listOpen
        }
        CollapsibleSection {
            expanded: root._listOpen && root._packagesAvailable
            EntryList {
                model: root._listOpen && root._packagesAvailable
                    ? Updates.packages : []
                textRole: "name"
                trailingRole: "to"
                emphasisRole: "aur"
                trailingSuffix: "AUR"
            }
        }
        ToggleRow {
            glyph: "󰚰"; label: "Track package updates"
            description: "Show pending count in bar"
            key: "updatesWidget"
            available: !SystemTools.ready || Updates.supported
            dependsNote: "No package manager"
        }
        CollapsibleSection {
            expanded: ShellSettings.updatesWidget
                && SystemTools.packageFamily === "pacman"
                && Updates.aurHelperAvailable
            ToggleRow {
                glyph: "󰮯"; label: "Include AUR packages"
                description: "Query "
                    + (SystemTools.hasParu ? "paru" : "yay")
                    + " for foreign package updates"
                key: "updatesIncludeAur"
            }
        }
        HintText { text: "Checks are read-only and never install updates." }
    }
}
