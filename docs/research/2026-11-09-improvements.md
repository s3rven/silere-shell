# Silere improvement research — 9 November 2026

The strongest next steps are better device information, more useful recovery
controls, and coverage of hardware changing while the shell is in use. Battery
details and a Bluetooth controller chooser are practical feature additions.
Headset modes and remembered dock setups offer more, with more integration work.

These recommendations were checked against this checkout at `fb213a2`, including the pending
Bluetooth and display-brightness fixes, the existing backlog, and the primary
sources linked below. Effort is relative: small extends an existing service;
medium adds state and device tests; large spans several services or backends.

The six primary recommendations below are implemented in the current working
tree. See [everyday use](../usage.md) for the controls and hardware requirements.
The later work and upstream investigations remain proposals.

## What Silere already covers

Timed and scheduled Do Not Disturb, timed Keep Awake, Presentation Mode,
screen-sharing notification privacy, per-app volume, device selection for audio,
external-display brightness, notification history retention, settings search,
keyboard navigation, diagnostic checks, signed updates, and rollback are already
present. They should not appear on a roadmap as new features. See
[everyday use](../usage.md), [scripting](../scripting.md), and
[testing](../testing.md).

The useful comparison with [Noctalia 5.4.1](https://github.com/noctalia-dev/noctalia/releases/tag/v5.4.1)
and [Dux 2.1.2](https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.1.2)
is how they make device state and recovery understandable. Silere already has
many of their everyday shell functions. My recommendation is to deepen those
functions before adding more large subsystems.

## Recommended order

| Priority | Improvement | Benefit | Effort |
|---|---|---|---|
| 1 | Extend Diagnostics with device checks and a shareable report | Explain why a control cannot work and give a useful next action | Small–medium |
| 2 | Battery health and charging details | Explain battery wear, power use, and multiple batteries | Small–medium |
| 3 | Bluetooth controller chooser | Make an internal radio plus USB adapter usable deliberately | Medium |
| 4 | Headset Listening / Calls modes | Change between playback quality and microphone support from Silere | Medium–large |
| 5 | Remember display preferences across dock changes | Keep the intended bar and popup display when connector names change | Medium–large |
| 6 | Keyboard-backlight control when supported | Add a useful laptop control without an always-visible empty row | Medium |

### 1. Make the existing Diagnostics page answer device questions

`SettingsMaintenanceSection.qml` already distinguishes real problems from absent
optional tools. Extend that page instead of adding another health dashboard.
Its current readiness checks concentrate on installed tools, fonts, notification
ownership, and theme integration.

Add a compact device check that reports the current output and microphone,
whether PipeWire is ready, the selected backlight, the latest brightness write
failure, blocked radios, and incomplete external-display discovery. Attach a
relevant action: retry discovery, open the device picker, open the configured
mixer, or show the applicable permission guidance. A package being installed
should not be the only evidence that its feature works.

Add `silere doctor --json` and a Copy diagnostic summary action using one
allowlisted report format. Include runtime versions, compositor, scale factors,
feature availability, and bounded error summaries. Leave notification bodies,
settings commands, wireless addresses, display serials, and full logs out of the
default report. The existing [bug report template](../../.github/ISSUE_TEMPLATE/bug_report.yml)
already asks users for versions, display setup, and relevant errors.

Acceptance: no healthy desktop is called broken for omitting an optional tool;
every displayed failure has a useful explanation; report generation works when
the shell is offline; copying a report causes no device changes.

### 2. Add battery details using the backend already loaded

`Battery.qml` currently focuses on aggregate charge, status, estimates, and
alerts. A details row or drawer could show battery health, stored/full energy,
and charging or discharging watts. Enumerate physical batteries when more than
one exists, while retaining the aggregate bar indicator.

Quickshell's supported
[UPowerDevice API](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.UPower/UPowerDevice/)
already exposes health availability, health percentage, energy, capacity, and
change rate. This makes a read-only first version feasible without a new daemon.
Unsupported measurements should be omitted rather than presented as zero.

Charge-limit information is a later extension. Current
[UPower device documentation](https://upower.freedesktop.org/docs/Device.html)
includes threshold capability and state properties, but those are not exposed
by every supported Quickshell/runtime combination. Probe support before using
them. Distinguish an actual configured limit from a temporary charging pause;
the existing PendingCharge state alone cannot establish the reason.

Acceptance: one battery, two batteries, an UPS-only desktop, missing health,
zero/unknown readings, and charge-limited operation all have accurate labels.
Health information must not introduce new repeating work while hidden.

### 3. Let users choose a Bluetooth controller

The service currently uses `Bluetooth.defaultAdapter`; the recent reliability
fixes improve how that controller's block state is read, but do not provide a
controller picker. Add a chooser only when multiple adapters exist, with
Automatic as the default and a clear indication of which controller owns the
listed devices.

The supported [Quickshell Bluetooth API](https://quickshell.org/docs/v0.3.1/types/Quickshell.Bluetooth/Bluetooth/)
already enumerates adapters and devices across adapters. Switching controllers
must release owned discovery and pairing state and reject late results from the
previous controller. A removed preferred controller must leave a usable
fallback. Treat `hci0` as a runtime identifier, not a permanent hardware identity.
Saved selection needs an additional stable-identity probe: the minimum
[adapter API](https://quickshell.org/docs/v0.3.1/types/Quickshell.Bluetooth/BluetoothAdapter/)
exposes an HCI identifier and object path, but no controller-address property.
A session-only chooser is a smaller first version.

Acceptance: two enabled controllers; a blocked internal controller and usable
USB radio; unplug during pairing; discovery already started by another app;
return of a preferred controller after its runtime identifier changes.

### 4. Add a bounded headset mode picker

Silere already labels a headset's call mode, but changing its profile requires
the external mixer. A Listening / Calls choice could handle the common case
without building a complete mixer. Show the capabilities actually available;
avoid assuming that every headset has the same playback/microphone trade-off.

There is a concrete implementation to review in the
[Silere fork's AudioMode service](https://github.com/OlaoluwaM/silere-shell/blob/52740a368b01132597df13b16d6bbc7906fc6b70/services/AudioMode.qml).
It discovers profiles and coordinates replacement audio nodes while switching.
Its audio and settings contracts differ from upstream, so it is a reference for
selected changes rather than a wholesale import.

[WirePlumber's wpctl interface](https://pipewire.pages.freedesktop.org/wireplumber/man/wpctl.html)
supports profile selection. Probe installed command capabilities, discover
profile indices, and keep the existing mixer handoff for unsupported cases.
Do not copy transient node IDs or fixed profile numbers into preferences.

Acceptance: volume and mute stay coherent through node replacement; a timeout
restores usable controls; unplugging mid-switch cannot replay an edit onto a
different device. Test a real headset in addition to metadata fixtures.

### 5. Make shell display preferences survive docking

`Monitors.qml` matches the preferred overlay display and disabled bars by
connector name. Start with remembering the intended physical display where it
can be identified reliably. Quickshell exposes model and serial information,
and documents that disconnected [ShellScreen objects](https://quickshell.org/docs/v0.3.1/types/Quickshell/ShellScreen/)
do not become live again when a monitor returns.

Use fresh screen objects after reconnect. Fall back to connector names when
identity is missing or ambiguous, and preserve existing settings during
migration. Two identical displays with blank serials must not silently exchange
preferences. A second stage could save separate shell layouts for laptop-only
and docked setups. Resolution, refresh rate, and monitor arrangement should
continue to be coordinated with the compositor's configuration.

Expand live tests alongside this work: mixed 100%/150%/200% outputs, scale changes
with a popup open, docking with the lid closed, and removal/restoration of the
last output. Upstream has open reports for
[mixed-scale crashes](https://github.com/quickshell-mirror/quickshell/issues/1446)
and [device-pixel-ratio updates](https://github.com/quickshell-mirror/quickshell/issues/1463).
Those reports concern other configurations; they motivate coverage and do not
establish a reproduced Silere defect or a QML-side fix.

### 6. Offer keyboard brightness on supporting machines

Add a keyboard-light control only when a backend reports a positive maximum.
Support Off and the hardware's actual steps; a two-step light should not behave
as though it has 100 distinct brightness levels. Reflect firmware-key changes
and rediscover the device after reconnect or resume.

The [UPower keyboard-backlight interface](https://upower.freedesktop.org/docs/KbdBacklight.html)
provides reads, writes, and change signals. Its documentation also describes
per-device object paths replacing the older fixed path, so discovery should not
assume a single hard-coded object. This is brightness control, not RGB effects.

Acceptance: absent hardware, maximum zero, two/three-step devices, permission
failure, firmware hotkeys, and daemon restart. The reference laptop's lack of a
supported light is not a reason to show an unavailable row on every machine.

## Useful later work

**Portable preferences.** Add export/import with a preview, schema validation,
migration, backup, and undo. Separate portable appearance/behavior preferences
from monitor identities, command paths, temporary DND deadlines, and other
machine/session state. Reuse the existing settings schema and migration path;
notification history should remain separate.

**Touch and assistive technology.** Existing tests exercise keyboard and
Accessible actions extensively. Add actual touch sequences and a screen-reader
walkthrough: list scrolling across sliders, reaching context actions without a
right mouse button, popup dismissal, and focus after reconnect. Adjust controls
where those checks reveal a problem instead of adding a global density setting
without evidence.

**Input methods and translations.** The current keyboard widget represents XKB
layout. Fcitx5/IBus state is a separate integration worth considering for broader
language use. Dux 2.1.2's
[Fcitx5 settings addition](https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.1.2)
is a relevant comparison, not evidence of demand among Silere users. Start with
language needs and an inventory of translatable strings before adding settings.

## Changes to avoid rushing

Keep automatic Bluetooth connection opt-in if it is ever added. Noctalia's
[Bluetooth service documentation](https://docs.noctalia.dev/noctalia/services/bluetooth/)
describes making its startup connection pass optional after queued attempts to
offline devices delayed other reconnections. The existing Silere backlog's
decision to rely on BlueZ/device reconnection remains reasonable.

Continue handing advanced routing, enterprise-network setup, passkey management,
launching, wallpaper choice, and locking to their configured tools until a
specific recurring workflow justifies taking ownership. A plugin marketplace,
new lock screen, or account/calendar sync would each create substantial ongoing
work beyond the gaps above.

Track Quickshell's [QML disk-cache pull request](https://github.com/quickshell-mirror/quickshell/pull/1049):
it was still open and unmerged when checked on 9 November. Its author's
performance results are for another shell. Verify compatibility with Silere's
minimum runtime and measure Silere before enabling or promising a gain. Keep
further performance decisions tied to the existing [benchmark harness](../performance.md).

## Implementation checks

The implementation adds mock-device coverage for incomplete display scans,
Bluetooth controller replacement, headset node replacement and backend failure,
and keyboard-light write failures and stale reads. The responsive layout fixtures
also populate battery details and the new lighting and headset controls without
requiring physical hardware. Real dock firmware, Bluetooth codecs, and keyboard
permission policies still need testing on the affected devices; these changes
do not establish support for every device or compositor.
