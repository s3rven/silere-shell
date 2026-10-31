import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "services"

Scope {
    id: root

    property string fixtures: Quickshell.env("SILERE_DAILY_FIXTURES")
    property int checks: 0
    property int failures: 0
    readonly property string uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    readonly property string identity: "a".repeat(64)
    readonly property string displayKey: "card1-DP-1:" + identity

    TestCase { id: input; when: false }
    FileView { id: file; blockAllReads: true; blockWrites: true; printErrors: false }

    function write(name, value): void {
        file.path = root.fixtures + "/" + name
        file.setText(value)
    }
    function read(name): string {
        file.path = root.fixtures + "/" + name
        file.reload()
        return file.text()
    }
    function check(ok: bool, label: string): void {
        root.checks++
        if (!ok) { root.failures++; console.error("PROBE-FAIL:", label) }
    }
    function waitFor(predicate, label: string, timeoutMs = 3000): bool {
        for (let i = 0; i < timeoutMs / 20; i++) {
            if (predicate()) { root.check(true, label); return true }
            input.wait(20)
        }
        root.check(false, label)
        return false
    }
    function profile(active: bool): string {
        return root.uuid + ":vpn:Work:" + (active ? "yes" : "no") + "\n"
    }
    function display(percent: int): string {
        return "card1-DP-1\t7\t" + root.identity + "\t" + percent + "\t100\n"
    }
    function vpnChecks(): void {
        root.write("vpn-profiles", root.profile(false))
        root.write("vpn-after-action", root.profile(true))
        root.write("vpn-calls", "")
        Vpn.requested = true
        root.waitFor(() => Vpn.profiles.length === 1 && !Vpn.refreshing, "VPN profiles load from the private helper")

        // An action completes while an older read still holds the inactive snapshot.
        Vpn.refresh()
        input.wait(60)
        Vpn.toggle(root.uuid)
        root.waitFor(() => Vpn.profiles.length === 1 && Vpn.profiles[0].active && !Vpn.refreshing,
            "an action during a profile read queues a fresh read instead of publishing stale state")
        root.check(Network.refreshes > 0 && Vpn.pendingUuid.length === 0,
            "a completed action also refreshes the bar indicator and releases the row")

        root.write("vpn-fail", "fail")
        Vpn.refresh()
        root.waitFor(() => !Vpn.refreshing && Vpn.lastError.length > 0, "VPN read failures are visible")
        root.write("vpn-fail", "")
        Vpn.refresh()
        root.waitFor(() => !Vpn.refreshing && Vpn.lastError.length === 0, "a successful VPN retry clears its read error")

        Vpn.refresh()
        input.wait(60)
        Network.toolAvailable = false
        root.waitFor(() => !Vpn.refreshing, "an unavailable VPN backend lets its bounded read finish")
        root.check(Vpn.profiles.length === 0, "a stale read cannot restore profiles after the backend disappears")
        Network.toolAvailable = true
        root.waitFor(() => Vpn.profiles.length === 1 && !Vpn.refreshing, "VPN profiles recover when the backend returns")

        root.write("vpn-profiles", root.profile(false))
        root.waitFor(() => Vpn.profiles.length === 1 && !Vpn.profiles[0].active && !Vpn.refreshing,
            "foreground polling catches external VPN changes without a bar state change", 7000)
        Vpn.requested = false
        root.check(!Vpn._wanted && !Vpn._refreshPending, "the closed VPN picker stops foreground refresh demand")
        root.write("vpn-calls", "")
        input.wait(5200)
        root.check(root.read("vpn-calls").length === 0, "the closed VPN picker launches no recurring helper")
        Idle.isIdle = true
        Vpn.requested = true
        root.check(!Vpn._wanted, "idle sessions do not poll VPN profiles")
        Vpn.requested = false
        Idle.isIdle = false
    }

    function brightnessChecks(): void {
        root.write("ddc-displays", root.display(20))
        root.write("ddc-calls", "")
        ShellSettings.ddcBrightnessEnabled = true
        MenuState.open = true
        root.waitFor(() => DisplayBrightness.displays.length === 1 && !DisplayBrightness.scanning,
            "external display discovery completes")

        DisplayBrightness.refresh(true)
        input.wait(50)
        DisplayBrightness.setPercent(root.displayKey, 65)
        input.wait(110)
        root.check(root.read("ddc-calls").indexOf("write") < 0,
            "brightness writes wait until discovery releases the display bus")
        root.waitFor(() => DisplayBrightness._writingKey.length === 0
                && root.read("ddc-calls").indexOf("write 65") >= 0,
            "a brightness change made during discovery is eventually written")
        root.check(DisplayBrightness.levelFor(root.displayKey) === 65,
            "discovery does not overwrite a queued slider value")

        root.write("ddc-calls", "")
        DisplayBrightness.refresh(true)
        input.wait(60)
        root.write("ddc-displays", root.display(75))
        DisplayBrightness.refresh(true)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.levelFor(root.displayKey) === 75,
            "refresh during discovery is queued and reads the new display value")

        root.write("ddc-calls", "")
        DisplayBrightness.setPercent(root.displayKey, 40)
        root.waitFor(() => DisplayBrightness._writingKey.length > 0, "the first coalesced brightness write starts")
        DisplayBrightness.setPercent(root.displayKey, 45)
        DisplayBrightness.setPercent(root.displayKey, 55)
        root.waitFor(() => DisplayBrightness._writingKey.length === 0
                && root.read("ddc-calls").indexOf("write 55") >= 0,
            "a busy brightness writer eventually applies the latest slider value")
        root.check(root.read("ddc-calls").indexOf("write 45") < 0,
            "intermediate slider values do not create extra brightness writes")

        DisplayBrightness.refresh(true)
        input.wait(60)
        ShellSettings.ddcBrightnessEnabled = false
        root.write("ddc-displays", root.display(90))
        ShellSettings.ddcBrightnessEnabled = true
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.levelFor(root.displayKey) === 90,
            "invalidation during discovery discards the old result and rescans the display")

        root.write("ddc-fail", "fail")
        DisplayBrightness.setPercent(root.displayKey, 80)
        root.waitFor(() => DisplayBrightness._writingKey.length === 0 && !DisplayBrightness.scanning
                && DisplayBrightness.lastError.length > 0 && DisplayBrightness.levelFor(root.displayKey) === 90,
            "a failed brightness write restores the measured level and keeps its error visible after discovery")
        root.write("ddc-fail", "")
        DisplayBrightness.setPercent(root.displayKey, 85)
        root.waitFor(() => DisplayBrightness._writingKey.length === 0 && DisplayBrightness.lastError.length === 0
                && root.read("ddc-calls").indexOf("write 85") >= 0,
            "a successful brightness retry clears its write error")

        root.write("ddc-calls", "")
        root.write("ddc-fail", "fail")
        DisplayBrightness.setPercent(root.displayKey, 80)
        root.waitFor(() => DisplayBrightness._writingKey.length > 0, "a fixture brightness write starts")
        ShellSettings.ddcBrightnessEnabled = false
        root.waitFor(() => DisplayBrightness._writingKey.length === 0, "an invalidated brightness write completes")
        root.check(DisplayBrightness.displays.length === 0 && DisplayBrightness.lastError.length === 0
                && Object.keys(DisplayBrightness._queued).length === 0,
            "a stale failed write cannot restore errors or queued work after brightness is disabled")

        MenuState.homeActive = false
        MenuState.settingsActive = false
        ShellSettings.ddcBrightnessEnabled = true
        root.check(!DisplayBrightness._wanted, "a remembered settings section does not scan from another page")
        MenuState.open = false
        ShellSettings.ddcBrightnessEnabled = false
    }

    function fontChecks(): void {
        root.write("font-families", "Fixture Sans,Fixture Sans Alias\nFixture Nerd Font Mono\nFixture Nerd Font\n")
        root.write("font-calls", "")
        FontScan.requestScan()
        root.waitFor(() => FontScan.scanned && !FontScan.scanning, "font discovery completes on demand")
        root.check(FontScan.families.indexOf("Fixture Sans Alias") >= 0
                && FontScan.iconFamilies.length === 1 && FontScan.iconFamilies[0] === "Fixture Nerd Font",
            "font discovery preserves text aliases and chooses one icon variant")

        root.write("font-hold", "hold")
        const calls = root.read("font-calls").length
        FontScan.scan(true)
        root.waitFor(() => root.read("font-calls").length > calls, "the first font refresh captures its snapshot")
        root.write("font-families", "Updated Sans\nUpdated Nerd Font\n")
        FontScan.scan(true)
        root.write("font-hold", "")
        root.waitFor(() => !FontScan.scanning && FontScan.families.indexOf("Updated Sans") >= 0,
            "a font refresh requested during a scan runs again and discovers newly installed fonts")

        root.write("font-fail", "fail")
        FontScan.scan(true)
        root.waitFor(() => !FontScan.scanning && FontScan.lastError.length > 0, "font scan failures are visible")
        root.check(FontScan.families.indexOf("Updated Sans") >= 0 && FontScan.iconFamilies.length === 1,
            "a failed font refresh keeps the last usable text and icon choices")
        root.write("font-fail", "")
        FontScan.requestScan()
        root.waitFor(() => FontScan.scanned && !FontScan.scanning && FontScan.lastError.length === 0,
            "a font scan recovers after a failed attempt")
        root.write("font-hold", "hold")
        const removalCalls = root.read("font-calls").length
        FontScan.scan(true)
        root.waitFor(() => root.read("font-calls").length > removalCalls,
            "a font scan is in flight when fontconfig disappears")
        SystemTools.hasFcList = false
        root.check(!FontScan.scanned && FontScan.families.length === 0 && FontScan.iconFamilies.length === 0,
            "removing fontconfig clears both font catalogues")
        root.write("font-families", "Recovered Sans\nRecovered Nerd Font\n")
        SystemTools.hasFcList = true
        root.write("font-hold", "")
        root.waitFor(() => FontScan.scanned && !FontScan.scanning
                && FontScan.families.indexOf("Recovered Sans") >= 0 && FontScan.iconFamilies.length === 1,
            "font discovery recovers with a fresh catalogue instead of the cancelled scan")
    }

    function sessionChecks(): void {
        root.write("session-state", "no")
        root.write("session-calls", "")
        root.check(!Session.canLockSleep, "lock and sleep is unavailable without its required tools")
        SystemTools.hasLoginctl = true
        SystemTools.scanRevision++
        if (!root.waitFor(() => Session.lockStateKnown && Session.canLockSleep,
                "a completed tool scan refreshes session readiness without restarting the shell")) {
            Session.refresh()
            root.waitFor(() => Session.lockStateKnown, "the explicit readiness refresh completes")
        }

        root.write("session-status-hold", "hold")
        const calls = root.read("session-calls").length
        Session.refresh()
        root.waitFor(() => root.read("session-calls").length > calls, "a session read captures the old lock state")
        root.write("session-state", "yes")
        Session.refresh()
        root.write("session-status-hold", "")
        root.waitFor(() => Session.locked, "a readiness refresh queued during a read gets the latest lock state")

        root.check(Session.lockAndSleep(), "a ready session starts its fixture lock request")
        root.waitFor(() => !Session.busy && SystemTools.commands.length === 1,
            "a confirmed fixture lock reaches the mocked suspend action")
        root.check(Compositor.commands.length === 1 && Compositor.commands[0][0] === "fixture-lock",
            "lock and sleep always requests its configured locker")

        root.write("session-wait-fail", "fail")
        Session.lockAndSleep()
        root.waitFor(() => !Session.busy && Session.lastError.length > 0, "a failed lock confirmation reports cancellation")
        root.check(SystemTools.commands.length === 1, "failed confirmation does not request suspend")
        root.write("session-wait-fail", "")

        root.write("session-wait-hold", "hold")
        const waits = root.read("session-calls").length
        Session.lockAndSleep()
        root.waitFor(() => root.read("session-calls").length > waits, "a lock confirmation is pending")
        SystemTools.hasLoginctl = false
        root.write("session-wait-hold", "")
        root.waitFor(() => !Session.busy, "losing session tools releases a pending lock request")
        input.wait(150)
        root.check(!Session.lockStateKnown && !Session.canLockSleep && SystemTools.commands.length === 1,
            "a late successful lock reply cannot suspend after the session tools disappear")
        const timeoutCalls = root.read("session-calls").length
        SystemTools.hasTimeout = false
        SystemTools.hasLoginctl = true
        input.wait(150)
        root.check(!Session.canLockSleep && root.read("session-calls").length === timeoutCalls,
            "session readiness stays off without a bounded status-read tool")
        SystemTools.hasTimeout = true
        root.waitFor(() => Session.lockStateKnown && Session.canLockSleep,
            "restoring all session tools recovers readiness without a restart")
    }

    Component.onCompleted: Qt.callLater(function() {
        root.vpnChecks()
        root.brightnessChecks()
        root.fontChecks()
        root.sessionChecks()
        if (root.failures === 0) console.info("PROBE-DAILY passed", root.checks, "checks")
        else console.error("PROBE-DAILY failed", root.failures, "of", root.checks, "checks")
    })
}
