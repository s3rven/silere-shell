# Daily-driver review

Reviewed on **24 October 2026**, against **e9b39f4** (after 1.4.4).

Implementation follow-up: [daily-driver changes and setup](daily-driver-changes.md).
The findings below describe the revision reviewed above.

Silere's strongest direction is a small, dependable shell with fast access to daily
controls. The next improvements should complete the interactions people already
use: keyboard navigation, private notifications, pairing devices, connecting to work
networks, and moving between a laptop and a desk.

This is a research and code review. The recommendations below are proposed work;
the review does not implement them. Behaviors identified from source are called out
separately from automated results. Pairing real devices, suspending the machine,
joining networks, and recording the desktop were not exercised.

**What already works well**

The code already includes captive-portal detection and sign-in, per-app audio
levels, microphone activity, notification actions and inline replies, searchable
history with retention settings, scheduled and timed DND, airplane mode, timed Keep
Awake, power profiles, night light, signed updates and rollback. Reduced motion,
high contrast, fractional scaling, popup unloading, bounded helper processes, and
idle gating are also established features.

These are useful foundations to preserve. The checked-in screenshots show a
consistent visual language; the largest opportunities are interaction completeness
and integration, with a smaller set of readability changes.

**Recommended order**

Sizes describe relative implementation scope, not calendar estimates. Each row
should be independently reviewable and should retain the current optional
dependency model.

| Order | Improvement | Daily benefit | Scope |
|---|---|---|---|
| 1 | Separate notification privacy from critical-alert bypass | Predictable behavior during meetings and recordings | Small–medium |
| 2 | Complete keyboard navigation | Use the control center and Settings without reaching for the pointer | Medium |
| 3 | Complete Bluetooth pairing | Pair keyboards and other passkey devices from a guided flow | Small handoff; large native agent |
| 4 | Guide and verify lock-before-sleep integration | Dependable laptop sleep behavior | Medium |
| 5 | Add saved VPN controls and advanced network handoffs | Connect to work or school without hunting for another tool | Medium |
| 6 | Ship an optional supervised startup path | Recover the bar and notification daemon after a crash | Medium |
| 7 | Extend readable type sizes and separate icons from text fonts | Make the interface comfortable on more displays | Medium |
| 8 | Add optional per-display DDC brightness | Control a docked desktop as conveniently as a laptop | Medium–large |
| 9 | Run compositor integration and compatibility checks in CI | Catch session regressions before users install an update | Medium |
| 10 | Extend performance measurements to daily workloads | Keep new features from adding persistent background cost | Small–medium |

**1. Make screen-sharing privacy independent of urgency**

Source finding: [`Notifications.qml`](../services/Notifications.qml) computes
`bypasses` from `notifCriticalBypass` and notification urgency, then uses it for
both DND and screen-sharing/fullscreen suppression. Both
`notifCriticalBypass` and `notifScreenShareSilence` default to true in
[`ShellSettings.qml`](../services/ShellSettings.qml). Consequently a critical app
notification is accepted for display during detected sharing by default. The UI
description in [`SettingsPopupsSection.qml`](../modules/menu/settings/SettingsPopupsSection.qml)
only says urgent alerts ignore DND.

The active-popup loader in [`shell.qml`](../shell.qml) also has no sharing gate.
Changing the sharing state does not currently retire already visible popups.
Automatic sharing detection is implemented for Hyprland; the niri backend has no
corresponding screencast signal, as also reflected in the usage guide.

First change: give privacy suppression its own decision, apply it to existing
popups as well as new arrivals, and make the text explain the actual behavior.
Provide a manual presentation toggle and IPC action on both compositors. Show
whether automatic detection is available. Keep necessary shell battery/temperature
warnings available through a clearly defined, content-free policy. Ordinary app
urgency should not override a promise to hide message content.

Acceptance: test normal and critical arrivals, existing persistent cards, and an
active inline reply when presentation mode begins. Verify that its end does not
replay stale cards. Later additions can include per-app history exclusions and
redacted previews; global persistence and retention controls already exist.

The notifications specification treats urgency as a sender hint. This is a reason
to keep privacy decisions separate from it, not a new requirement imposed by the
specification. [Desktop Notifications hints](https://specifications.freedesktop.org/notification/latest/hints.html).

**2. Finish keyboard navigation in the shared controls**

Source finding: [`ActionButton.qml`](../modules/common/ActionButton.qml),
[`ToggleRow.qml`](../modules/menu/controls/ToggleRow.qml),
[`SliderTrack.qml`](../modules/menu/controls/SliderTrack.qml), and the other shared
controls expose accessibility actions, but lack ordinary Tab traversal and key
activation. [`usage.md`](usage.md) explicitly describes a mostly pointer-operated
interface. Accessibility metadata alone does not put an `Item` into Qt's Tab chain;
`activeFocusOnTab` defaults to false. [Qt Item focus](https://doc.qt.io/qt-6/qml-qtquick-item.html#activeFocusOnTab-prop),
[Qt keyboard focus](https://doc.qt.io/qt-6/qtquick-input-focus.html).

First change: establish focus behavior in shared controls, including a visible
focus ring, Tab/Shift+Tab, Enter/Space activation, arrow-key sliders, list selection,
and focus restoration when a picker closes. Keep pointer, keyboard, and accessible
actions on the same guarded methods. Include Home, Settings navigation, Wi-Fi,
Bluetooth, tray menus, and notification actions in the follow-up passes.

Acceptance: open the menu by its compositor shortcut, choose an audio output,
change a setting, navigate a picker, and close the menu entirely with the keyboard.
Test actual key events, disabled/hidden controls, pooled list delegates, and focus
return to the previous application on Hyprland and niri.

**3. Offer a complete Bluetooth pairing path**

Source finding: [`Bluetooth.qml`](../services/Bluetooth.qml) handles discovery,
pair/connect attempts, cancellation, trust, and timeouts. When pairing fails,
[`BluetoothList.qml`](../modules/menu/BluetoothList.qml) tells the user to start
`blueman-applet` or `bt-agent` if a passkey is needed. Silere does not supply the
PIN/passkey/confirmation UI for that case.

First change: offer a discoverable handoff to an installed Bluetooth manager, with
an explanation before the user reaches a failed attempt. Longer term, evaluate a
proper BlueZ agent with PIN entry, displayed passkeys, confirmation, cancellation,
and timeout handling. Quickshell's documented 0.3.1 Bluetooth module does not expose
an agent type; treat native pairing as an integration project rather than assuming
a QML dialog alone completes it. [BlueZ Agent API](https://bluez.readthedocs.io/en/latest/agent-api/),
[Quickshell Bluetooth types](https://quickshell.org/docs/v0.3.1/types/Quickshell.Bluetooth/).

Acceptance: pair a keyboard requiring a displayed code, a confirmation device, and
a device needing no input; cancel each flow; remove the adapter during a request.
Keep discovery and pairability ownership bounded, as the current service does.

**4. Make lock-before-sleep setup visible**

Source finding: [`Settings.qml`](../config/Settings.qml) launches `systemctl suspend`
or `loginctl suspend` directly. [`troubleshooting.md`](troubleshooting.md) documents
that the power menu sleeps without locking and delegates locking to the idle daemon.
Checking that a lock command exists does not verify that this integration is set up.

First change: add a session-readiness item that explains whether an external locker
and sleep hook are configured, with a supported setup recipe for each compositor.
Offer an explicit Lock and Sleep action when readiness can be confirmed. A lock
request is asynchronous: do not assume starting a command or receiving a successful
`loginctl lock-session` reply proves the secure lock is already established.

Use the existing locker/idle-daemon integration and an appropriate readiness or
sleep-inhibition mechanism. hypridle documents its sleep hooks and lock-notify
inhibition; logind exposes sleep signals and inhibitors.
[hypridle configuration](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/),
[logind D-Bus API](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

Acceptance: cover lock failure, absent idle daemon, an existing lock, lid-close
sleep, and resume. Test capability logic with fixtures; validate real sleep in a
deliberate manual session.

**5. Complete the common networking journeys**

Source finding: [`Network.qml`](../services/Network.qml) detects an active VPN and
reads its address; Home offers address copying, not saved VPN activation. Unknown
enterprise security types are profile-only, and networks with an empty SSID are
excluded from the scan list. [`WifiList.qml`](../modules/menu/WifiList.qml) labels
an unsupported unsaved network as "Not supported" and disables its row.

First change: show saved VPN profiles with connect/disconnect and progress, and
offer an advanced network-manager handoff for hidden Wi-Fi, enterprise profiles,
certificates, and IP/DNS settings. List multiple active tunnels if present. Use
profile UUIDs for actions and handle secret-agent requests rather than placing
passwords in process arguments. NetworkManager supports profile activation by UUID
and interactive secrets via an agent. [NetworkManager nmcli manual](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/nmcli.html).

Acceptance: exercise duplicate profile names, authentication cancellation, a failed
tunnel, multiple VPNs, IPv6-only tunnels, and profile removal during activation.
Retain the existing portal sign-in and retry behavior.

**6. Make crash recovery an installable option**

Source finding: [`install.sh`](../scripts/install.sh) installs compositor startup
commands. The repo supports externally supplied `silere-shell.service` units, and
[`CompositorHyprland.qml`](../services/CompositorHyprland.qml) can recover certain
compositor/socket failures only when a unit runs the matching checkout. The repo
ships update units, but no shell service template.

First change: ship an optional session-bound user service with `Restart=on-failure`,
a restart delay, and a rate limit. Integrate it with the compositor's session
environment and shutdown lifecycle. Keep one startup owner, preserve the duplicate
guard, and retain the existing direct-launch path. [systemd service restart behavior](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#Restart=).

Acceptance: crash an isolated test instance, confirm that it returns once, then
verify that an intentional stop and compositor logout do not restart it. Cover
multiple checkouts and stale compositor environment variables.

**7. Improve readable sizing and font choice**

Source finding: the `uiScale` schema stops at 1.15.
[`Settings.qml`](../config/Settings.qml) derives default body text from 12 logical
pixels and permits some secondary text at 8–9 logical pixels.
[`FontScan.qml`](../services/FontScan.qml) lists only Nerd Font families, while
[`ShellText.qml`](../modules/common/ShellText.qml) gives text and icon glyphs the
same font family. Existing high contrast and reduced motion are strengths to keep.

First change: add a larger comfortable text preset, test increasing the supported
range toward 150–200%, and make narrow layouts reflow or scroll. Separate the
interface text font from a dependable icon font or vector icon component so people
can use their preferred readable font. Include non-Latin notification text in the
verification. This is an application sizing improvement; compositor display scaling
already scales logical pixels. [Qt scalability guidance](https://doc.qt.io/qt-6/scalability.html).

Acceptance: inspect Home, Settings, notification replies, and connectivity lists
at the new sizes on a small laptop and at fractional display scales, including
long labels and fallback glyphs.

**8. Add external-monitor brightness without constant probing**

Source finding: [`Brightness.qml`](../services/Brightness.qml) controls one selected
`brightnessctl` backlight. External displays exposed as `ddcci` backlight devices
can already fit that path, but there is no direct DDC/CI backend or per-output UI.

First change: add optional `ddcutil` support for displays without a backlight device,
with a slider per display, cached identity mapping, bounded/coalesced writes,
hotplug/resume rediscovery, and a per-display disable option. Preserve the current
laptop backend. ddcutil supports monitor brightness through DDC/CI and explicitly
does not control laptop panels. [ddcutil documentation](https://www.ddcutil.com/).

Acceptance: cover two monitors, a slow or unsupported display, permissions errors,
unplugging during a write, and docking/resume without writing a stale value to a
different display. Keep discovery demand-driven and measure its background cost.

**9. Put the existing session probes in CI**

Source finding: [the validation workflow](../.github/workflows/validate.yml) runs
rolling Arch with the available Quickshell package and offscreen probes. It does
not invoke `dev/test-panels.sh` or `dev/test-screens.sh`, although
[`dev/check.sh`](../dev/check.sh) invokes both. Screen removal currently uses a
nested KWin, which is valuable protocol coverage but does not establish behavior
on both advertised compositors. The documented floor is Quickshell 0.3.1 / Qt 6.9.

First change: add a nested-compositor CI job using the existing probes, then add
focused Hyprland and niri smoke/interaction coverage. Exercise a reproducible
minimum-supported dependency build as well as current packages. Document which
parts of the supported floor are actually tested.

Acceptance: CI fails on missing required integration tooling rather than reporting
a skipped probe as coverage. Include popup focus, output removal, compositor
reconnection, and keyboard input. Add mocked backend-loss/reappearance cases for
NetworkManager, BlueZ, and PipeWire without restarting the user's real services.

**10. Measure the workloads people spend their day in**

Source finding: [`performance.md`](performance.md) and
[`perf-history.md`](perf-history.md) explain the measurements carefully, and
[`bench.sh`](../scripts/bench.sh) measures CPU, memory, threads, and descriptors.
The latest recorded release rows are 1.4.3; 1.4.4 is explicitly unmeasured.

First change: record the next release's cold and warm baseline and add scenarios
for media playback, visualizer use, multiple displays, repeated popup/list cycles,
and lock/idle/resume. Track menu opening latency and frame pacing alongside PSS,
CPU, helper processes, and descriptor growth. Compare identical configurations on
the same hardware, and use longer repeated samples before labeling a leak or
regression.

The live shell in this review ran from a separate installed directory. No new
controlled performance benchmark of this checkout was collected; the published
1.4.3 numbers should not be presented as measurements of this revision.

**Optional workflow additions after the core work**

Peer research supports making common workflows easy to reach. The current
[DMS overview](https://duxlabs.dev/docs/1.6/dankmaterialshell/overview) documents
launcher, VPN, clipboard, and brightness integration, while
[Noctalia's widget catalog](https://docs.noctalia.dev/noctalia/bar/widgets/) offers
launcher, clipboard, privacy, keyboard-layout, and screenshot entry points. These
are product references, not evidence that Silere must adopt either architecture.

The smallest useful additions would be configurable shortcuts to an existing app
launcher, clipboard manager, screenshot tool, and network manager, with visible
labels and an easy way to discover secondary mouse actions. A keyboard-layout and
Caps Lock indicator would also help people who switch languages daily. Hooks and
IPC already exist; build on them before designing a general plugin runtime.

If a native launcher is wanted later, start with apps, open windows, shell actions,
and Settings search. Quickshell already supplies
[DesktopEntries](https://quickshell.org/docs/v0.3.1/types/Quickshell/DesktopEntries/),
but its documented
[DesktopEntry execution](https://quickshell.org/docs/v0.3.1/types/Quickshell/DesktopEntry/)
has terminal and field-code limitations that need explicit handling. Broader file
indexing, calendar sync, weather, and a plugin marketplace should follow demonstrated
demand and a background-resource budget.

**Validation recorded for this review**

The required commands were run on Quickshell **0.3.2** and Qt **6.12.0**:

| Command | Result |
|---|---|
| `bash scripts/test-qml-headless.sh` | Passed: 193 QML files |
| `bash dev/test-logic.sh` | Passed: 1,994 checks |
| `bash dev/check.sh` | Passed: zero warnings after rerunning with local socket access |

The full run included startup and malformed-settings checks, 91 popup interaction
behaviors, four screen-removal checks, 182 mutation states over 55 surfaces, layout
fit, and 1,340 UI stress checks across 120 cycles. The initial restricted run had
socket-access errors and a scrollbar stress assertion; the complete unrestricted
rerun passed. No scrollbar defect is established by that initial result.

These checks validate the current baseline. They do not validate the proposed
features or replace hardware testing of sleep, pairing, networking, or DDC.
