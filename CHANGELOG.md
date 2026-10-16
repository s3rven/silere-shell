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

- Notifications tagged with `x-canonical-private-synchronous` or `x-dunst-stack-tag` replace the
  same app's earlier card with that tag, so volume and brightness scripts written for dunst, mako
  or swaync show one card instead of a stack.
- History search ignores accents, so `cafe` finds `Café`.

### Changed

- The workspace marker and the window title glide through quick successive switches instead of
  restarting their motion each time.
- The OSD level follows a held volume or brightness key smoothly instead of jumping in steps.
- The VPN row shows and copies an IPv6 address when the tunnel has no IPv4 one.
- Visualizer bars fade toward their tops and stand on the bar's edge line, so loud peaks no longer
  cover the media title or break the outline.

### Fixed

- Settings search matches the start of words, so `lock` finds the screen lock instead of the clock.
- Paired Bluetooth devices are trusted once they connect, from the menu or any other tool,
  so they can reconnect on their own when switched on.
- A disconnect, forget, power or reset confirmation left armed across a suspend asks again
  instead of acting on the next click.
- Tray menus no longer show stray separator lines left around entries the app hides.
- The VPN row in Home appears even when the network widget is hidden from the bar.
- Scrolling quickly through calendar months names the month you are heading to and keeps the
  grid changing, instead of fading it blank until you stop.
- Values in the bar sit on the same line as the clock and window title instead of a pixel lower.
- Volume, brightness, battery and microphone readings sit with their icons, without the spare half
  character on each side that left the bar's dividers off-centre.
- The multi-window badge on workspace app icons and the rail and search hover labels stay crisp
  on fractionally scaled displays.

## Releases

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
