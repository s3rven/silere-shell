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

- Search notification history by app, title or message; Clear removes only the visible results.
- Calendar week start and week-number visibility under Clock settings.
- Screen-reader names for the Wi-Fi password field and the missed-notification badge.
- Do Not Disturb, night light, power mode, Wi-Fi, Bluetooth and airplane mode each toggle
  over IPC, for a keybind that changes one without opening a panel.
- The installer offers a key that opens the menu, and leaves a combination the Hyprland
  config already uses alone.
- The bar and OSD blur what is behind them on Hyprland 0.56 and niri 26.04 or newer, as do popups set to match the bar's opacity.

### Changed

- The clock highlights while its calendar is open and keeps hour and minute digits in stable-width slots.

### Fixed

- Pill hover values reset when the bar sleeps or the widget hides.
- Calendar today markers follow the clock across midnight.
- The tray menu closes when the bar moves to the other screen edge.
- A notification with no app name is named the same in history as in the app rail, and search finds it.
- Escape closes an open Settings dropdown before it closes the menu.
- A tray tile waits for its own icon when the bar hands it a different app.
- The compositor restart watcher recovers once inotify-tools is installed.
- The alert dismiss timeout is disabled when libnotify is missing.
- A notification progress bar draws the percentage its sender set.
- A notification asking to outlast the popup limit is held at the limit instead of the default.
- Night light holds its memory steady over a long session.
- A failing package check backs off instead of retrying every three minutes.
- Popups open and close over a window without a bright flash.
- Notification history grows to fit its entries instead of cutting off the last one.
- Switching menu pages from a keybind resizes the panel in one motion.
- A downloaded copy of Silere is no longer described as package-managed; Settings › Updates points it at the installer.

## Releases

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
