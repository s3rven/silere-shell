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

- Settings search by feature name or configuration key, with direct section links and Ctrl+F.
- Optional notification history expiry after a day, week or month, with no background polling.
- Drag a notification popup sideways to dismiss it.
- Show an active VPN and its address in the Connectivity card and the network widget's hover text; click the card row to copy the address.
- Turn on Do Not Disturb for an hour or until morning from its row in the menu.
- Right-click a history entry to remove it, or middle-click it to jump to the app that sent it.

### Changed

- Keep settings search collapsed behind a compact heading icon until opened.
- Refine search with stable input geometry, clear-query and close actions, match counts, grouped results and shortcut hints.
- Settings search also finds a setting by the label it shows, names the setting each result opens, and scrolls to it with a brief highlight.
- Edit custom screen-lock commands in Interface settings, with Save, Revert and input validation.
- Stop colour-selection springs while their settings controls are hidden or disabled.
- Switching menu tabs uses about 10% less CPU.
- Round the notification search field and the calendar month button to match the round buttons beside them.
- New icons for the Interface and Spacing settings pages.
- The audio visualizer responds to quieter passages instead of sitting nearly flat.
- The centered visualizer draws twice as many bars.
- The visualizer setting says when it is paused by fullscreen or needs the media widget.
- The audio visualizer runs at Eco while on battery and returns to its preset on the charger.

### Fixed

- Moving diagonally toward an open tray submenu no longer switches to another submenu passed on the way.
- Hidden colour swatches no longer accept accessibility actions, and selection rings stay inside their current options.
- Reject incomplete command escapes and empty program names before enabling the lock action.
- Preserve the last successful package update count when its checker exits with an error.
- Keep updated notification history entries when deletion uses an older snapshot.
- Notifications from terminal agents no longer show literal `**` around bold words.
- A short pause no longer restarts the visualizer and its warm-up.
- Clicking a notification from an app with several windows, such as kitty, keeps the window the app brings forward instead of jumping to another.
- A failed Bluetooth connection suggests checking that the device is on and nearby before forgetting it.
- Clear stale windows, workspaces and overview state when niri disconnects.
- Cancel unfinished slider gestures when their range or step changes.
- Require a fresh confirmation after its time window expires, even when the cleanup timer is delayed.

## Releases

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
