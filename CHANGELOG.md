# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

### Added

- A Bluetooth device that refuses to connect or pair now says so on its row.

### Changed

- Disconnecting the current Wi-Fi network takes a second tap to confirm.

### Fixed

- Keybinds open the menu, calendar and quick actions under the widget that opens them, not at the screen edge.
- Bar Roundness reads Round once the corners reach half the bar's height, instead of a number the bar cannot draw.
- Notification history no longer holds read-state for notifications it has already dropped.
- A double-click on a connected Bluetooth device no longer disconnects it in one gesture.
- Notifications and the OSD sit at the edge of a monitor whose bar is turned off, rather than clearing a bar that is not on it.
- Popup borders draw at the same weight on every side.

## Releases

- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
