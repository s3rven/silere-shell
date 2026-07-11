import QtQuick
import "../../config"
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        UpdateStatusCard {
            flat: true
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
            flat: true
            glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
            title: "System packages"
            status: Updates.statusText
            meta: Updates.managerLabel
            detail: Updates.lastFailed ? Updates.lastError : ""
            detailError: Updates.lastFailed
            statusColor: Updates.lastFailed ? Theme.warning
                : Updates.isChecking ? Theme.accent
                : Updates.ready && Updates.count === 0 ? Theme.success
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
        ToggleRow {
            glyph: "󰚰"; label: "Track package updates"
            description: "Pending-update badge in the bar"
            checked: ShellSettings.updatesWidget
            onToggled: ShellSettings.updatesWidget = !ShellSettings.updatesWidget
            available: !SystemTools.ready || Updates.supported
            dependsNote: "No package manager"
        }
        ToggleRow {
            glyph: "󰥔"; label: "Daily update check"
            checked: ShellUpdate.timerEnabled
            enabled: !ShellUpdate.timerBusy
            available: ShellUpdate.timerSupported
            dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
            onToggled: ShellUpdate.setTimerEnabled(!ShellUpdate.timerEnabled)
        }
        HintText { text: "Checks never install anything on their own." }
    }
}
