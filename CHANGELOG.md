# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

**Upgrading:** re-run the installer. Matugen now writes
`$XDG_CONFIG_HOME/matugen/silere-shell.json` instead of a file inside the checkout,
and until your `config.toml` points there, wallpaper colours stop changing and the
shell falls back to its bundled palette. If that file has an unpaired
`# silere-shell` marker the installer declines to touch it and says so; repair the
pair, then re-run.

### Added

- **Include AUR packages** toggle under Settings › System › Updates, counting
  updates through paru or yay when one is installed. On by default. Checks stay
  read-only and never install anything.
- Settings › Theme and Settings › System › Maintenance now name whether Matugen is
  missing or has simply not written a palette yet, instead of presenting the
  bundled colours as if they came from the wallpaper.

### Changed

- Matugen palettes live-reload from a user-writable JSON file, which also makes
  read-only packaged installs work.
- Text no longer scales on hover or press. A scaled glyph is drawn at one size and
  resampled to another, which softened labels on fractionally scaled outputs.
  Surfaces still react; the text on them stays put.
- Text renders with distance fields rather than snapping to a device pixel grid
  that fractional scaling has already resampled away.
- Buttons, pills, chips, toggles, media controls and slider handles share one hover
  and press response, quicker in than out.
- The bundled fallback accent is Silere's own default accent rather than white, so
  a system without Matugen looks like a fresh install rather than a stark one.
- Renamed the theme Source option from Neutral to Custom, and the accent picker's
  custom swatch to Mix, so the two no longer share a name.

### Removed

- Keyboard navigation and its accessibility metadata. Tab order, arrow-key
  stepping, focus rings, the settings sidebar's keyboard cursor and every
  `Accessible` role, name and description are gone; the shell is pointer-driven.
  Escape still steps back and closes, scrolling works everywhere it did, and the
  Wi-Fi password field still takes typed input. **Screen readers can no longer
  describe the shell.**

### Fixed

- The media visualizer and track marquee froze on the only visible bar whenever
  focus moved to a monitor with the bar disabled.
- The screenshot watcher respawned every 60 seconds forever when no screenshot
  directory existed, instead of giving up on a failure restarting cannot fix.
- Notification history mislabelled days after a daylight-saving change, where a
  23-hour day put every entry one bucket early and produced two **Yesterday**
  headings.
- A hung update check, package check or VPN lookup now recovers through one shared
  bounded-process timeout instead of three hand-rolled timers.
- Optional-tool and font detection refresh cleanly at runtime.
- The workspace and window models no longer rebuild for a compositor event
  carrying nothing they read; it fired 420 times in two hours of ordinary use.
- Changing the clock's date style, or middle-clicking the clock, wrote the settings
  file twice in a row.
- The first settings section opened in a session no longer stutters compiling every
  shared control before it can draw.
- Settings row names keep a readable floor when space runs short; the value
  shortens first.
- Dropdown options and the Wi-Fi and Bluetooth list placeholders sat 4px shorter
  than neighbouring rows above 100% interface scale, putting dividers off the
  shared rhythm.
- The Wi-Fi password field is marked sensitive to input methods, so an IME or
  on-screen keyboard no longer capitalises the first character of a case-sensitive
  key or keeps it in predictive-text history.
- The settings panel eases to its new height when a category collapses instead of
  snapping.
- The palette card no longer bulges while switching theme Source between Custom and
  Wallpaper.
- Corrected the generated Cava profile's smoothing range.

## Releases

- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
