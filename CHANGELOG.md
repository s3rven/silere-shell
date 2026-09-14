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

- The notifications page carries a rail of the apps that have sent one; picking an app
  narrows the page to it, and Clear then takes only that app's history.
- The audio visualizer can run along the bar's underline, spanning its full width.

### Changed

- Workspace taps, window drops, special-workspace entries and OSD nudges settle on one
  timing instead of five.
- Power Mode on the Home page opens the list of available profiles.
- The notifications page is taller and wider, and reads at one width whether or not the
  app rail is showing.
- Notification popups are wider.
- Device and option rows highlight the full row and follow the card’s corner.
- Maintenance names the lock and night-light programs in one line each.
- The low-battery and overheating alerts pulse on each threshold, then hold steady.
- The visualizer draws denser bars on wider tracks.

### Fixed

- A paused player no longer leaves the underline lit.

## Releases

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
