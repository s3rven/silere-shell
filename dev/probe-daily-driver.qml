import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth as Bt
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
    Component { id: bluetoothFactory; BluetoothProbe {} }
    Component { id: audioModeFactory; AudioModeProbe {} }
    Component {
        id: radioFactory
        QtObject {
            property string adapterId: "hci0"
            property string name: "Fixture radio"
            property int state: Bt.BluetoothAdapterState.Blocked
            property bool enabled: false
            property bool discovering: false
            property var devices: ({ values: [] })
        }
    }

    function write(name, value): void {
        file.path = root.fixtures + "/" + name
        file.reload()
        file.text()
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
        Vpn.requestList(root, true)
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
        Vpn.requestList(root, false)
        root.check(!Vpn._wanted && !Vpn._refreshPending, "the closed VPN picker stops foreground refresh demand")
        root.write("vpn-calls", "")
        input.wait(5200)
        root.check(root.read("vpn-calls").length === 0, "the closed VPN picker launches no recurring helper")
        Idle.isIdle = true
        Vpn.requestList(root, true)
        root.check(!Vpn._wanted, "idle sessions do not poll VPN profiles")
        Vpn.requestList(root, false)
        Idle.isIdle = false

        // Home only asks for a peek; there is no open picker to force backend recovery.
        Vpn._peekedAt = 0
        Vpn.peek()
        root.waitFor(() => Vpn._peek && Vpn.refreshing, "a background VPN peek starts")
        Network.toolAvailable = false
        Network.toolAvailable = true
        root.waitFor(() => Vpn.profiles.length === 1 && !Vpn.refreshing && !Vpn._peek,
            "a backend restart during a background VPN peek obtains a fresh profile list")
        root.check(!Vpn.requested, "background VPN recovery does not acquire a picker request")
        Network.toolAvailable = false
        Network.toolAvailable = true
        root.waitFor(() => Vpn.profiles.length === 1 && !Vpn.refreshing,
            "a backend restart invalidates the recent VPN peek cache")
        root.write("vpn-calls", "")
        Vpn._peekedAt = 0
        Vpn.peek()
        root.waitFor(() => !Vpn.refreshing && !Vpn._peek, "a background VPN peek finishes its request")
        root.check(root.read("vpn-calls").trim() === "list",
            "a background VPN peek launches one helper instead of queueing its own duplicate")

        Vpn._peekedAt = 0
        root.write("vpn-profiles", root.profile(false))
        root.write("vpn-calls", "")
        Vpn.peek()
        root.waitFor(() => root.read("vpn-calls").length > 0, "a background VPN read captures its snapshot")
        input.wait(60)
        root.write("vpn-profiles", root.profile(true))
        Vpn.refresh()
        root.waitFor(() => !Vpn.refreshing && !Vpn._peek && Vpn.profiles[0]?.active === true,
            "a background VPN peek preserves a refresh queued while its previous read was running")

        Vpn._peekedAt = 0
        root.write("vpn-profiles", root.profile(false))
        root.write("vpn-calls", "")
        Vpn.peek()
        root.waitFor(() => root.read("vpn-calls").length > 0, "a background VPN read is pending before idle")
        input.wait(60)
        Idle.isIdle = true
        root.waitFor(() => !Vpn.refreshing, "the VPN read completes while idle")
        root.check(Vpn._peek && !Vpn._wanted, "an idle VPN peek retains its unfulfilled one-shot demand")
        Idle.isIdle = false
        root.waitFor(() => !Vpn.refreshing && !Vpn._peek && Vpn.profiles[0]?.active === false,
            "waking finishes the paused VPN peek with a fresh snapshot")

        Vpn._peekedAt = 0
        root.write("vpn-calls", "")
        Vpn.peek()
        for (let i = 0; i < 6; i++) {
            Network.toolAvailable = false
            root.write("vpn-profiles", root.profile(i % 2 === 1))
            input.wait(20)
            Network.toolAvailable = true
            input.wait(20)
        }
        root.waitFor(() => !Vpn.refreshing && !Vpn._peek && Vpn.profiles[0]?.active === true,
            "repeated VPN backend restarts settle on the newest snapshot")
        const settledCalls = root.read("vpn-calls")
        input.wait(300)
        root.check(root.read("vpn-calls") === settledCalls && !Vpn.requested && !Vpn._refreshPending,
            "VPN restart recovery leaves no recurring helper or unowned foreground request")
    }

    function powerChecks(): void {
        // a target picked from UPower's default can turn out to be the live mode, and then no request runs
        const live = root.read("power-live").trim()
        if (live.length > 0)
            root.waitFor(() => PowerProfiles.profile === live, "the power mode settles on the live daemon's value")
        const want = PowerProfiles.profile === "balanced" ? "power-saver" : "balanced"
        ShellSettings.powerProfileAc = want === "balanced" ? "power-saver" : "balanced"
        ShellSettings.powerProfileBattery = ShellSettings.powerProfileAc
        const originalAc = ShellSettings.powerProfileAc
        const originalBattery = ShellSettings.powerProfileBattery
        root.write("power-calls", "")
        root.write("power-hold", "hold")
        root.write("power-fail", "fail")
        PowerProfiles.setProfile(want)
        root.waitFor(() => root.read("power-calls").length > 0, "a power-mode request reaches the private helper")
        root.check(ShellSettings.powerProfileAc === originalAc,
            "an unfinished power-mode request does not replace the remembered AC preference")
        root.write("power-hold", "")
        root.waitFor(() => !PowerProfiles._setter.running && PowerProfiles.lastError === "Permission denied",
            "a rejected power change reports its useful error")
        root.check(ShellSettings.powerProfileAc === originalAc && ShellSettings.powerProfileBattery === originalBattery,
            "a rejected power change leaves both source preferences intact")

        root.write("power-calls", "")
        root.write("power-fail", "")
        root.write("power-hold", "hold")
        PowerProfiles.setProfile(want)
        root.waitFor(() => root.read("power-calls").length > 0, "a power-mode retry starts")
        Battery.onBattery = true
        PowerProfiles._sourceSettleTimer.stop()
        root.write("power-hold", "")
        root.waitFor(() => !PowerProfiles._setter.running, "the power-mode retry completes")
        root.check(PowerProfiles.lastError === "" && ShellSettings.powerProfileAc === want
                && ShellSettings.powerProfileBattery === originalBattery,
            "success remembers the source where the request began even if the charger changes")

        root.write("power-calls", "")
        root.write("power-hold", "hold")
        PowerProfiles.setProfile(want)
        root.waitFor(() => root.read("power-calls").length > 0, "a battery power-mode request is pending")
        ShellSettings.powerProfileRemember = false
        root.write("power-hold", "")
        root.waitFor(() => !PowerProfiles._setter.running, "a request can finish after remembering is disabled")
        root.check(ShellSettings.powerProfileBattery === originalBattery,
            "disabling remembered modes prevents an in-flight success from saving a preference")

        ShellSettings.powerProfileRemember = true
        ShellSettings.powerProfileBattery = ""
        root.write("power-hold", "hold")
        PowerProfiles._setter.timeoutMs = 100
        PowerProfiles.setProfile(want)
        root.waitFor(() => !PowerProfiles._setter.running && PowerProfiles.lastError === "Power mode change timed out",
            "a hung power helper times out", 5000)
        root.check(ShellSettings.powerProfileBattery === "" && PowerProfiles._pendingPreference === null,
            "a timeout discards the pending preference even if the terminated helper later exits")
        root.write("power-hold", "")
        PowerProfiles._setter.timeoutMs = 8000

        root.write("power-calls", "")
        root.write("power-hold", "hold")
        PowerProfiles.setProfile(want)
        root.waitFor(() => root.read("power-calls").length > 0, "a power change can be interrupted by service removal")
        SystemTools.hasPowerProfilesCtl = false
        root.waitFor(() => !PowerProfiles._setter.running, "service removal releases its writer")
        root.write("power-hold", "")
        SystemTools.hasPowerProfilesCtl = true
        PowerProfiles._acceptSetResult(0, false, "")
        root.check(ShellSettings.powerProfileBattery === "" && PowerProfiles._pendingPreference === null,
            "a late success cannot save a preference from a retired service")
        if (PowerProfiles.profile.length > 0) {
            root.write("power-calls", "")
            PowerProfiles.lastError = "Previous failure"
            PowerProfiles.setProfile(PowerProfiles.profile)
            root.check(PowerProfiles.lastError === "" && ShellSettings.powerProfileBattery === PowerProfiles.profile
                    && root.read("power-calls").length === 0,
                "selecting the active mode remembers it and clears an old error without another helper")
        }
        Battery.onBattery = false
        PowerProfiles._sourceSettleTimer.stop()

        // a test shell shares the system bus with the desktop it runs on: a charger edge must not write the real mode
        const restoreWas = ShellSettings.powerProfileAc
        ShellSettings.powerProfileAc = PowerProfiles.profile === "balanced" ? "power-saver" : "balanced"
        PowerProfiles._sandboxed = true
        PowerProfiles._sourceSettleTimer.triggered()
        root.check(!PowerProfiles._setter.running, "a sandboxed shell leaves the desktop's power mode alone on a charger edge")
        PowerProfiles._sandboxed = false
        ShellSettings.powerProfileAc = restoreWas

        // a mode key changes the mode outside the menu; it is the latest choice for the source it lands on
        PowerProfiles._startSettleTimer.stop()
        ShellSettings.powerProfileAc = "balanced"
        ShellSettings.powerProfileBattery = "power-saver"
        PowerProfiles._noteProfileChange("balanced", "performance")
        root.check(ShellSettings.powerProfileAc === "performance" && ShellSettings.powerProfileBattery === "power-saver",
            "a mode changed outside the menu is remembered for the current source only")
        PowerProfiles._sourceSettleTimer.restart()
        PowerProfiles._noteProfileChange("performance", "balanced")
        PowerProfiles._sourceSettleTimer.stop()
        PowerProfiles._startSettleTimer.restart()
        PowerProfiles._noteProfileChange("performance", "power-saver")
        PowerProfiles._startSettleTimer.stop()
        root.check(ShellSettings.powerProfileAc === "performance",
            "a mode switch beside a charger edge or UPower's first read is not remembered")
        ShellSettings.powerProfileRemember = false
        PowerProfiles._noteProfileChange("performance", "power-saver")
        ShellSettings.powerProfileRemember = true
        root.check(ShellSettings.powerProfileAc === "performance",
            "a mode changed outside the menu is not remembered while remembering is off")
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

        const secondKey = "card1-DP-2:" + root.identity
        root.write("ddc-displays", root.display(90)
            + "card1-DP-2\t8\t" + root.identity + "\t30\t100\n")
        DisplayBrightness.refresh(true)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.displays.length === 2,
            "brightness discovery includes a second external display")
        root.write("ddc-calls", "")
        root.write("ddc-fail-connector", "card1-DP-1")
        DisplayBrightness.setPercent(root.displayKey, 80)
        root.waitFor(() => DisplayBrightness._writingKey === root.displayKey,
            "a brightness write starts on the display that will reject it")
        DisplayBrightness.setPercent(root.displayKey, 75)
        DisplayBrightness.setPercent(secondKey, 55)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness._writingKey.length === 0
                && root.read("ddc-calls").indexOf("write 55") >= 0,
            "one display's failed write preserves a pending brightness change for another display")
        root.check(DisplayBrightness.levelFor(root.displayKey) === 90
                && DisplayBrightness.levelFor(secondKey) === 55
                && root.read("ddc-calls").indexOf("write 75") < 0,
            "a failed display returns to its measured level without retrying its rejected queued value")
        root.write("ddc-fail-connector", "")

        root.write("ddc-displays", root.display(35))
        root.write("ddc-scan-fail", "fail")
        DisplayBrightness.invalidate()
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.displays.length === 1
                && DisplayBrightness.levelFor(root.displayKey) === 35 && DisplayBrightness.lastError.length > 0,
            "a scan that fails after one display keeps that display's brightness control")
        root.write("ddc-scan-fail", "")
        DisplayBrightness.refresh(false)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.lastError.length === 0,
            "an incomplete display scan can retry immediately instead of waiting for the freshness cache")

        // a TV or dock that never answers DDC/CI: listed for its switch, named in the warning, never written
        const silentKey = "card1-DP-2:" + root.identity
        root.write("ddc-displays", root.display(35) + "card1-DP-2\t8\t" + root.identity + "\t-2\t100\n")
        root.write("ddc-scan-fail", "fail")
        DisplayBrightness.refresh(true)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.displays.length === 2
                && DisplayBrightness.lastError.indexOf("DP-2 does not answer") === 0,
            "a display that never answers is listed and named in the warning")
        root.check(DisplayBrightness.displays.find(d => d.key === silentKey)?.unreadable === true
                && DisplayBrightness.displays.find(d => d.key === root.displayKey)?.unreadable === false,
            "only the display that did not answer is marked unreadable")
        root.write("ddc-calls", "")
        DisplayBrightness.setPercent(silentKey, 60)
        input.wait(250)
        root.check(root.read("ddc-calls").indexOf("write") < 0, "an unreadable display takes no brightness write")
        // the real script skips a switched-off display's read, so the list comes back whole
        root.write("ddc-scan-fail", "")
        root.write("ddc-displays", root.display(35) + "card1-DP-2\t8\t" + root.identity + "\t-1\t100\n")
        DisplayBrightness.setEnabled(silentKey, false)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.displays.length === 2
                && DisplayBrightness.lastError.length === 0 && DisplayBrightness._lastScan > 0,
            "switching off an unreadable display ends its warning and the scan caches again")
        root.write("ddc-displays", root.display(35))
        DisplayBrightness.setEnabled(silentKey, true)
        root.waitFor(() => !DisplayBrightness.scanning && DisplayBrightness.displays.length === 1,
            "switching the display back on rescans")

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

    function audioNode(mode: string, serial: string, address = "aa:bb:cc:dd:ee:ff"): var {
        return { id: 101, name: "bluez_output.aa_bb_cc_dd_ee_ff.1", ready: true, audio: {},
            properties: { "device.api": "bluez5", "device.id": 77, "api.bluez5.address": address,
                "api.bluez5.profile": mode, "object.serial": serial } }
    }
    function audioProfiles(active: int): string {
        return JSON.stringify([{ id: 77, type: "PipeWire:Interface:Device", info: { params: {
            EnumProfile: [{ index: 1, name: "a2dp-sink", priority: 20 },
                { index: 2, name: "headset-head-unit", priority: 10 }], Profile: [{ index: active }]
        } } }])
    }
    function audioModeChecks(): void {
        root.write("audio-calls", "")
        root.write("audio-profiles", root.audioProfiles(1))
        MenuState.open = true
        Audio.sink = root.audioNode("a2dp-sink", "1")
        const mode = audioModeFactory.createObject(root)
        root.waitFor(() => mode.available && mode.current === "listening", "headset modes load from the private PipeWire fixture")
        root.write("audio-list-fail", "fail")
        mode.refresh(true)
        root.waitFor(() => mode.lastError.length > 0, "headset profile read errors remain visible")
        root.write("audio-list-fail", "")
        mode.refresh(true)
        root.waitFor(() => mode.available && mode.lastError === "", "a successful headset read clears its previous read error")
        mode.setMode("calls")
        root.waitFor(() => mode._setSucceeded, "a headset mode change completes its private setter")
        root.check(mode.switching && Audio.profileSwitching, "audio controls remain held until the requested headset returns")
        Audio.sink = { ready: true, audio: {}, properties: { "device.api": "alsa", "device.id": 3 } }
        input.wait(120)
        root.check(mode.switching && Audio.profileSwitching, "a temporary speaker fallback cannot finish the headset change")
        root.write("audio-profiles", root.audioProfiles(2))
        Audio.sink = root.audioNode("headset-head-unit", "2", "11:22:33:44:55:66")
        input.wait(120)
        root.check(mode.switching, "a different headset reusing the device id cannot finish the pending change")
        Audio.sink = root.audioNode("headset-head-unit", "3")
        root.waitFor(() => !mode.switching && !Audio.profileSwitching && mode.lastError === "",
            "the requested headset mode restores audio controls when the matching device returns")
        root.waitFor(() => mode.available && mode.current === "calls", "headset profiles refresh after the node replacement")

        root.write("audio-set-fail", "fail")
        mode.setMode("listening")
        root.waitFor(() => !mode.switching && mode.lastError.length > 0,
            "a rejected headset profile change releases controls and reports an error")
        root.check(!Audio.profileSwitching, "failed headset requests cannot leave volume controls disabled")
        root.write("audio-set-fail", "")
        mode.setMode("listening")
        root.waitFor(() => mode._setSucceeded, "a headset retry reaches its confirmation phase")
        mode._settleTimer.stop()
        mode._settleTimer.triggered()
        root.check(!mode.switching && !Audio.profileSwitching && mode.lastError.length > 0,
            "a headset that never returns hits the confirmation deadline and restores controls")

        mode.setMode("listening")
        root.waitFor(() => mode._setSucceeded && mode.switching, "another headset change starts before a backend restart")
        Audio.backendReady = false
        root.check(!mode.switching && !Audio.profileSwitching,
            "a PipeWire disconnect immediately restores audio controls")
        Audio.backendReady = true
        root.write("audio-list-hold", "hold")
        root.write("audio-calls", "")
        mode.refresh(true)
        root.waitFor(() => root.read("audio-calls").includes("list"), "a headset profile read captures the old device")
        Audio.sink = root.audioNode("a2dp-sink", "4", "11:22:33:44:55:66")
        root.write("audio-profiles", "[]")
        root.write("audio-list-hold", "")
        input.wait(500)
        root.check(!mode.available, "late profile reads cannot publish capabilities for a replacement headset")
        mode.destroy()
        Audio.sink = null
        MenuState.open = false
    }

    function keyboardLine(level: int, second = false): string {
        return "/org/freedesktop/UPower/KbdBacklight/fixture" + (second ? "1" : "0")
            + "\t" + level + "\t2\tfixture-keyboard-" + (second ? "1" : "0") + "\n"
    }
    function keyboardChecks(): void {
        root.write("keyboard-devices", root.keyboardLine(1) + root.keyboardLine(2, true))
        root.write("keyboard-calls", "")
        // the slider lives in Home, so discovery runs there, not behind every surface
        MenuState.open = true
        MenuState.homeActive = true
        SystemTools.hasBusctl = true
        KeyboardBrightness.rescan()
        root.waitFor(() => KeyboardBrightness.ready && KeyboardBrightness.devices.length === 2
            && KeyboardBrightness.currentLevel === 1, "keyboard lights discover their discrete hardware levels")
        KeyboardBrightness.setLevel(0)
        root.waitFor(() => KeyboardBrightness._confirmedLevel === 0 && KeyboardBrightness.currentLevel === 0,
            "keyboard lighting supports turning the light fully off")
        root.write("keyboard-list-hold", "hold")
        root.write("keyboard-calls", "")
        KeyboardBrightness.rescan()
        root.waitFor(() => root.read("keyboard-calls").includes("list"), "a keyboard read captures an older level")
        KeyboardBrightness.setLevel(2)
        root.waitFor(() => KeyboardBrightness._confirmedLevel === 2, "a newer keyboard level reaches the private writer")
        root.write("keyboard-list-hold", "")
        input.wait(400)
        root.check(KeyboardBrightness.currentLevel === 2, "an older keyboard read cannot overwrite the user's newer level")
        // the other order: the read starts after the edit and samples the light before the write reaches it
        const levelsSeen = []
        const noteLevel = () => levelsSeen.push(KeyboardBrightness.currentLevel)
        KeyboardBrightness.currentLevelChanged.connect(noteLevel)
        root.write("keyboard-list-hold", "hold")
        root.write("keyboard-calls", "")
        KeyboardBrightness.setLevel(0)
        KeyboardBrightness.rescan()
        root.waitFor(() => root.read("keyboard-calls").includes("list") && KeyboardBrightness._confirmedLevel === 0,
            "a keyboard read that began before the write finishes after it")
        root.write("keyboard-list-hold", "")
        input.wait(600)
        KeyboardBrightness.currentLevelChanged.disconnect(noteLevel)
        root.check(levelsSeen.every(level => level === 0) && KeyboardBrightness.currentLevel === 0,
            "a keyboard read begun before a write lands cannot flash the old level back: " + levelsSeen.join(","))
        KeyboardBrightness.setLevel(2)
        root.waitFor(() => KeyboardBrightness._confirmedLevel === 2, "the keyboard fixture returns to its earlier level")
        input.wait(400)

        root.write("keyboard-set-fail", "fail")
        KeyboardBrightness.setLevel(1)
        root.waitFor(() => KeyboardBrightness.lastError.length > 0 && KeyboardBrightness.currentLevel === 2,
            "keyboard write failures report an error and restore the last confirmed level")
        root.write("keyboard-set-fail", "")
        root.write("keyboard-calls", "")
        KeyboardBrightness.setLevel(0)
        KeyboardBrightness.preferredKey = KeyboardBrightness.devices[1].key
        input.wait(250)
        root.check(!root.read("keyboard-calls").includes("write"),
            "changing the keyboard target drops a queued edit instead of replaying it onto another light")
        root.check(KeyboardBrightness.currentLevel === 2,
            "changing the keyboard target presents its own hardware level: " + KeyboardBrightness.currentLevel)
        KeyboardBrightness.setLevel(1)
        root.waitFor(() => KeyboardBrightness._confirmedLevel === 1 && !KeyboardBrightness.lastError,
            "a keyboard retry targets the newly selected light and clears its error")
        KeyboardBrightness._pollTimer.stop()
        root.write("keyboard-devices", root.keyboardLine(1))
        root.write("keyboard-list-fail", "fail")
        KeyboardBrightness.rescan()
        root.waitFor(() => KeyboardBrightness.devices.length === 1 && KeyboardBrightness.lastError.length > 0,
            "a keyboard light that fails its read is reported while the lights that answered keep their sliders")
        root.write("keyboard-list-fail", "")
        root.write("keyboard-devices", root.keyboardLine(1) + root.keyboardLine(2, true))
        KeyboardBrightness.rescan()
        root.waitFor(() => KeyboardBrightness.devices.length === 2 && !KeyboardBrightness.lastError,
            "a complete keyboard read clears the earlier failure")
        root.write("keyboard-list-hold", "hold")
        root.write("keyboard-calls", "")
        KeyboardBrightness.rescan()
        root.waitFor(() => root.read("keyboard-calls").includes("list"), "a keyboard discovery starts before a tool restart")
        SystemTools.hasBusctl = false
        root.write("keyboard-devices", "")
        SystemTools.hasBusctl = true
        root.write("keyboard-list-hold", "")
        root.waitFor(() => !KeyboardBrightness.ready && KeyboardBrightness.devices.length === 0,
            "a stale discovery cannot restore keyboards after the backend restarts")
        input.wait(400)
        root.check(!KeyboardBrightness.ready, "the fresh discovery confirms that the removed keyboards stay absent")
        MenuState.open = false
        MenuState.homeActive = false
        Idle.isIdle = true
        root.check(!KeyboardBrightness._pollTimer.running, "keyboard polling stops when controls close or the session is idle")
        Idle.isIdle = false
        SystemTools.hasBusctl = false
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

    function bluetoothChecks(): void {
        const service = bluetoothFactory.createObject(root)
        const first = radioFactory.createObject(root)
        const second = radioFactory.createObject(root, { adapterId: "hci1" })
        const lookup = service._rfkillLookup
        lookup.command = ["bash", "-c", 'cat "$1/rfkill-state"; echo probe >> "$1/rfkill-calls"; sleep 0.15',
            "rfkill-fixture", root.fixtures]
        service._blockRefresh.interval = 50
        root.write("rfkill-state", "hci0\t1\nhci1\t0\n")
        service._adapters = [first, second]
        service._defaultAdapter = first
        root.check(service.adapter === first && service.adapterChoice === "" && service.adapterChoices.length === 3,
            "automatic Bluetooth selection follows the default and lists both controllers")
        root.waitFor(() => service.hardBlocked && !lookup.running,
            "the selected Bluetooth controller reports its hardware block")

        root.write("rfkill-state", "hci0\t0\nhci1\t1\n")
        MenuState.open = true
        root.waitFor(() => !service.hardBlocked && !lookup.running,
            "opening the menu refreshes a hardware switch while BlueZ still reports Blocked")
        root.check(service.blocked && first.state === Bt.BluetoothAdapterState.Blocked,
            "lifting only the hardware block does not require a BlueZ power-state change")
        root.write("rfkill-state", "hci0\t1\nhci1\t0\n")
        root.waitFor(() => service.hardBlocked,
            "moving the hardware switch with the menu open refreshes its control")
        Idle.isIdle = true
        root.check(!service._blockRefresh.running,
            "idle sessions stop recurring Bluetooth switch probes")
        MenuState.open = false
        Idle.isIdle = false
        root.check(!service._blockRefresh.running,
            "closing the menu stops recurring Bluetooth switch probes")
        root.waitFor(() => !lookup.running, "the last Bluetooth switch probe finishes")

        root.write("rfkill-state", "hci0\t0\nhci1\t1\n")
        QuickActionsState.open = true
        root.waitFor(() => !service.hardBlocked && !lookup.running,
            "Quick Actions also refreshes a hardware block without opening the menu")
        QuickActionsState.open = false
        root.check(!service._blockRefresh.running,
            "closing Quick Actions releases Bluetooth switch polling")

        // Hold an old hci0 snapshot through a controller change. The hci1
        // state must come from a new read even though both remain Blocked.
        root.write("rfkill-state", "hci0\t1\nhci1\t1\n")
        const calls = root.read("rfkill-calls").length
        service.refreshBlockState()
        root.waitFor(() => root.read("rfkill-calls").length > calls,
            "a Bluetooth switch probe captures the old controller's state")
        root.write("rfkill-state", "hci0\t1\nhci1\t0\n")
        root.check(service.selectAdapter("hci1") && service.adapter === second && service.adapterChoice === "hci1",
            "the Bluetooth controller chooser selects the requested live controller")
        let staleBlock = false
        const observe = function() { if (service.hardBlocked) staleBlock = true }
        service.hardBlockedChanged.connect(observe)
        root.waitFor(() => !lookup.running && lookup.generation === service._rfkillGeneration
                && !service.hardBlocked,
            "switching blocked Bluetooth controllers obtains a fresh switch reading")
        root.check(!staleBlock,
            "an old controller's in-flight rfkill reading cannot disable the replacement controller")
        service.hardBlockedChanged.disconnect(observe)

        root.write("rfkill-fail", "fail")
        root.write("rfkill-actions", "")
        service.toggle()
        root.waitFor(() => !service._unblockWanted && root.read("rfkill-actions").length > 0,
            "a failed rfkill command clears its pending enable request")
        root.waitFor(() => !lookup.running, "the failed unblock's switch refresh finishes")
        const replacement = radioFactory.createObject(root, { adapterId: "hci1" })
        service._adapters = [first, replacement]
        root.check(service.adapter === first && !service.selectAdapter("missing"),
            "replacing a selected controller under the same hci id falls back without selecting different hardware")
        root.waitFor(() => service.adapterChoice === "", "losing a selected radio releases its session preference")
        service._adapters = []
        root.check(!service.hardBlocked && !service._blockRefresh.running,
            "unplugging a blocked controller clears its cached switch state")
        service.destroy()
        first.destroy()
        second.destroy()
        replacement.destroy()
    }

    function alertCalls(): var {
        return root.read("alert-calls").split("\n").filter(line => line.length > 0)
    }
    function alertChecks(): void {
        root.write("alert-calls", "")
        root.check(!SystemAlerts.armed, "the alert fixture starts with its notification tool unavailable")
        const headset = percent => ({ address: "AA", name: "Fixture headset", connected: true, percent: percent })
        Bluetooth._devices = [headset(18)]
        input.wait(30)
        root.check(SystemAlerts._btWarned.AA !== true && root.alertCalls().length === 0,
            "an unavailable notification tool does not consume a Bluetooth battery warning")
        SystemTools.hasNotifySend = true
        SystemTools.scanRevision++
        root.waitFor(() => root.alertCalls().length === 1 && SystemAlerts._btWarned.AA === true,
            "a completed tool scan sends the waiting Bluetooth battery warning")

        Bluetooth._devices = [headset(-1)]
        input.wait(30)
        root.check(SystemAlerts._btReadings.length === 1 && SystemAlerts._btWarned.AA === true,
            "a connected device retains its warning through a missing battery reading")
        Bluetooth._devices = [headset(17)]
        input.wait(60)
        root.check(root.alertCalls().length === 1,
            "recovering the same low battery reading does not send another warning")

        ShellSettings.osdBatteryWarn = false
        Bluetooth._devices = [headset(30)]
        input.wait(30)
        root.check(SystemAlerts._btWarned.AA !== true,
            "a charging device rearms its warning even while battery alerts are disabled")
        Bluetooth._devices = [headset(18)]
        input.wait(30)
        root.check(SystemAlerts._btWarned.AA !== true && root.alertCalls().length === 1,
            "disabled alerts do not consume a new low battery warning")
        ShellSettings.osdBatteryWarn = true
        root.waitFor(() => root.alertCalls().length === 2 && SystemAlerts._btWarned.AA === true,
            "reenabling battery alerts reports the connected device's low battery")

        const keyboard = { address: "BB", name: "Fixture keyboard", connected: true, percent: 8 }
        Bluetooth._devices = [headset(18), keyboard]
        root.waitFor(() => root.alertCalls().length === 3 && SystemAlerts._btWarned.BB === true,
            "a second low device receives its own warning")
        const keyboardAlert = root.alertCalls()[2] || ""
        root.check(keyboardAlert.indexOf("Fixture keyboard battery low") >= 0
                && keyboardAlert.indexOf("8%") >= 0,
            "the queued alert names the device and its actual reading")
        Bluetooth._devices = [headset(18)]
        input.wait(30)
        root.check(SystemAlerts._btWarned.BB !== true && SystemAlerts._btWarned.AA === true,
            "disconnecting one Bluetooth device rearms only its own warning")
        Bluetooth._devices = [headset(18), keyboard]
        root.waitFor(() => root.alertCalls().length === 4,
            "reconnecting a still-low device warns once for the new connection")
        Bluetooth._devices = [{ address: "CC", name: "-x pad", connected: true, percent: 5 }]
        root.waitFor(() => root.alertCalls().length === 5,
            "a device whose name starts with a dash is warned")
        root.check((root.alertCalls()[4] || "").indexOf(" -- -x pad battery low") >= 0,
            "a dash-led device name reaches notify-send after the end of its options")
        Bluetooth._devices = []
        input.wait(30)
        root.check(Object.keys(SystemAlerts._btWarned).length === 0,
            "disconnecting all Bluetooth devices releases their warning state")
    }

    function sessionChecks(): void {
        root.write("alert-calls", "")
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

        // the hint still reads locked from before the press: nothing can confirm the new lock
        root.check(Session.lockAndSleep(), "a session whose hint is already locked still takes the press")
        root.waitFor(() => !Session.busy && Session.lastError.indexOf("already marked locked") >= 0,
            "a hint already set before the lock request cancels sleep")
        root.check(Compositor.commands.length === 1 && SystemTools.commands.length === 0
                && root.read("session-calls").indexOf("wait") < 0,
            "a stale hint still locks the screen but never waits on it or suspends")
        root.waitFor(() => root.alertCalls().length === 1, "a stale hint's cancelled sleep raises an alert")
        root.write("alert-calls", "")
        root.write("session-state", "no")
        Compositor.commands = []

        root.check(Session.lockAndSleep(), "a ready session starts its fixture lock request")
        root.waitFor(() => !Session.busy && SystemTools.commands.length === 1,
            "a confirmed fixture lock reaches the mocked suspend action")
        root.check(Compositor.commands.length === 1 && Compositor.commands[0][0] === "fixture-lock",
            "lock and sleep always requests its configured locker")

        root.write("session-wait-fail", "fail")
        Session.lockAndSleep()
        root.waitFor(() => !Session.busy && Session.lastError.length > 0, "a failed lock confirmation reports cancellation")
        root.check(SystemTools.commands.length === 1, "failed confirmation does not request suspend")
        root.waitFor(() => root.alertCalls().length === 1, "cancelled sleep reaches the private notification helper")
        const sleepAlert = root.alertCalls()[0] || ""
        root.check(sleepAlert.indexOf("--urgency=critical") >= 0
                && sleepAlert.indexOf(Session.lastError) >= 0,
            "a cancelled sleep raises an alert, because the menu that started it has closed")
        root.write("session-wait-fail", "")

        root.write("session-wait-hold", "hold")
        // the pre-lock status read lands in the same log, so count waits alone
        const waits = root.read("session-calls").split("wait").length
        Session.lockAndSleep()
        root.waitFor(() => root.read("session-calls").split("wait").length > waits, "a lock confirmation is pending")
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

        Compositor.commands = []
        root.write("session-status-hold", "hold")
        const beforeCalls = root.read("session-calls").length
        root.check(Session.lockAndSleep(), "a lock request can wait on its initial session read")
        root.waitFor(() => root.read("session-calls").length > beforeCalls,
            "the initial lock-state read is pending before session tools disappear")
        SystemTools.hasLoginctl = false
        root.write("session-status-hold", "")
        root.waitFor(() => !Session.busy, "cancelling the initial lock-state read releases its request")
        input.wait(150)
        root.check(Compositor.commands.length === 0 && SystemTools.commands.length === 1,
            "a cancelled pre-lock read cannot launch the locker or suspend")
        SystemTools.hasLoginctl = true
        root.waitFor(() => Session.lockStateKnown && Session.canLockSleep,
            "readiness recovers after cancelling an initial lock-state read")
    }

    Component.onCompleted: Qt.callLater(function() {
        root.vpnChecks()
        root.powerChecks()
        root.brightnessChecks()
        root.bluetoothChecks()
        root.audioModeChecks()
        root.keyboardChecks()
        root.fontChecks()
        root.alertChecks()
        root.sessionChecks()
        if (root.failures === 0) console.info("PROBE-DAILY passed", root.checks, "checks")
        else console.error("PROBE-DAILY failed", root.failures, "of", root.checks, "checks")
    })
}
