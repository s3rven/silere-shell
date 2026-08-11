# Changelog

Notable changes to Silere Shell. The active section follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them.

The updater tracks `main`, not tags, so a running install gets changes as they land
rather than when a version is published here. The settings file has its own
`__version` and migrates separately.

This file stays focused on work since the latest release. Completed notes move to
[`docs/releases`](docs/releases/) and remain linked below.

## [Unreleased]

### Changed

- Session-bus helper commands now have hard time limits, so a stalled power,
  battery, notification, location or update-timer backend cannot leave its
  shell control busy forever.
- The media visualizer now paints its small canvas immediately instead of
  handing CPU images through a dedicated render thread. Measured on the
  reference session, this cuts visualizer CPU by about a fifth without
  changing its look.
- Slider handles now use Silere's narrow rectangular control shape instead of
  circular knobs. Their rails have squarer ends, clearer hover/focus contrast,
  and inset endpoints that keep handles out of adjacent labels. The rail no
  longer changes thickness on hover, and Home, End, Page Up and Page Down work
  consistently on both regular and colour sliders.
- Compact widget and tray spacing is slightly tighter, and high-contrast focus
  rings are stronger against the rest of the high-contrast palette.

### Fixed

- Power Mode now confirms successful changes against the daemon and keeps
  retrying a failed corrective read, rather than leaving its optimistic label
  stale after a transient backend failure.
- Truncated client labels no longer split emoji, combining marks, flags or joined
  emoji sequences, and a tray icon with no usable image now uses a complete
  grapheme for its fallback badge.
- An urgent workspace outside the visible page no longer risks a transient QML
  binding loop while the bar is laying itself out.
- System maintenance now reports a missing `libnotify` dependency when battery
  and temperature alerts are configured but cannot be sent.

## Releases

- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
