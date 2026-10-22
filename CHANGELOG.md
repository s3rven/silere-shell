# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

### Added

- Drag the scrollbar in menu pages, notification history and long dropdown lists to move through them.
- Click the network or Bluetooth bar widget to open Home for connection and radio controls.
- On Hyprland, popups wait in history while the screen is shared, with a red mark by the clock
  until the share ends.
- Power Mode remembers what you picked on battery and on the charger, and restores it when you
  plug in or unplug.
- Connected Bluetooth devices send one alert when their battery drops below 20%.
- A Bluetooth headset that an app's microphone switches to call quality shows "Call mode" in the
  OSD and the output list.
- Keep Awake can switch itself off after one or two hours. Expand its row on Home to choose,
  and the row shows when it ends.

### Changed

- Clock and Workspaces settings gather their single-option cards into fewer groups.
- The Notifications page and its app list are ready when you open them, instead of the list
  arriving after the panel has widened.
- Returning to Now Playing within a few seconds shows the page and its cover at once instead of
  building them again.
- Cover art downloads only while the menu shows it.
- Long window and media titles shorten on a crowded bar instead of pushing controls aside, and
  switching compact mode resizes widgets at once.
- The wave visualizer's line fades as it rises, so loud passages no longer strike through the
  media title.
- Notifications show markdown code fences, inline code and links as plain text.
- A notification that repeats the one before it word for word replaces it in history.
- A notification with only a title shows up to three lines of it in the popup and two in history.

### Fixed

- At fractional scales such as 1.25, outlines stay sharp on settings chips, dropdowns and
  buttons, the side rail selection, the notification history with its app list, and popup buttons.
- Hidden bars reject retained clock, media, tray and workspace actions and stop their
  media and workspace animations until shown again.
- Very dark custom accents keep workspace indicators, update icons and clock seconds readable.
  Switch knobs keep their contrast against the selected track with custom colours and high contrast.
- A missing or crashed night-light stop helper reports a failure and cancels a queued
  replacement instead of treating the old night light as stopped.
- A crashed night-light state check keeps the last known state instead of treating its
  signal number as proof that no night light is running.
- Battery and temperature warnings stay visible long enough to read at the default OSD timeout,
  instead of disappearing almost immediately.
- Volume feedback drops its temporary device name even when a newer brightness popup is showing.
- Brightness controls keep queued changes when an older refresh finishes during a drag or scroll.
- A charger change during a slow power-mode command still restores the mode for the current
  power source once the command finishes.
- The bar's volume reads 0% while muted, matching the menu, the OSD and the microphone, instead
  of the level it returns to.
- Bluetooth turned off by blueman or `rfkill` turns back on from Silere, instead of reading as
  blocked by the hardware switch.
- Open Wi-Fi networks can be joined on Quickshell 0.3.1 instead of showing as not supported.
- Checking for a Silere update no longer fails now and then with an invalid compositor list.
- An update blocked by many local files names the first one and how to clear it, instead of
  stopping without a reason.
- The one-line install no longer ends with `curl: Failed writing body`.
- Scrolling a volume or brightness control after a sideways touchpad swipe starts a fresh step.
- The bar underline no longer flashes when a notification is replaced or restored, and stays still
  during idle. Full-width underline effects spread their glow across the whole bar.

### Removed

- The Sweep style for screenshot underline feedback. Screenshots is now an on/off switch that
  keeps the Flash style.
- The OSD's Feedback for setting. The OSD shows both volume and brightness.

## Releases

- [1.4.3](docs/releases/1.4.3.md) — 2026-10-18
- [1.4.2](docs/releases/1.4.2.md) — 2026-10-11
- [1.4.1](docs/releases/1.4.1.md) — 2026-10-10
- [1.4.0](docs/releases/1.4.0.md) — 2026-10-09
- [1.3.0](docs/releases/1.3.0.md) — 2026-10-05
- [1.2.0](docs/releases/1.2.0.md) — 2026-09-27
- [1.1.1](docs/releases/1.1.1.md) — 2026-09-17
- [1.1.0](docs/releases/1.1.0.md) — 2026-09-17
- [1.0.0](docs/releases/1.0.0.md) — 2026-09-07
- [0.9.0](docs/releases/0.9.0.md) — 2026-08-30
- [0.8.0](docs/releases/0.8.0.md) — 2026-08-22
- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
