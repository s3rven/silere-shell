# Changelog

Notable changes to Silere Shell. The active section follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them.

The updater follows signed stable version tags. The settings file has its own
`__version` and migrates separately.

This file stays focused on work since the latest release. Completed notes move to
[`docs/releases`](docs/releases/) and remain linked below.

## [Unreleased]

- Made optional-tool and font detection refresh cleanly at runtime, with stable
  capability state and explicit backend failure tracking.
- Added reusable process retry/exit health and Cava runtime/config status so
  failed visualizer starts can be diagnosed without affecting the rest of the shell.
- Fixed the generated Cava profile's smoothing range and documented its
  runtime-only configuration lifecycle.
- Made Matugen palettes live-reload from a user-writable JSON file, including
  installer migration and working support for read-only packaged installs.
- Added AUR packages to the update count through paru or yay when one is
  installed, with a new **Include AUR packages** toggle under Settings › System ›
  Updates. It is on by default, so an existing install with an AUR helper will
  start counting those updates. Checks stay read-only and never install anything.
- Gave buttons, pills, chips, toggles and media controls one consistent hover and
  press response, quicker on the way in than on the way back out.
- Renamed the theme Source option from Neutral to Custom, and the accent picker's
  own custom swatch to Mix, so the two no longer share one name.
- Fixed the settings panel snapping to its new height when a category collapses
  instead of easing with it.
- Fixed the palette card bulging outward while switching theme Source between
  Custom and Wallpaper.

## Releases

- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
